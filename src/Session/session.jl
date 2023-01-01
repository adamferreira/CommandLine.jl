
abstract type AbstractSession end

struct SessionConfig
    """
    ignorestatus::Bool: If true (defaults to false), then the Cmd will not throw an error if the return code is nonzero.

    detach::Bool: If true (defaults to false), then the Cmd will be run in a new process group, allowing it to outlive the julia process and not have Ctrl-C passed to it.
    windows_verbatim::Bool: If true (defaults to false), then on Windows the Cmd will send a command-line string to the process with no quoting or escaping of arguments, even arguments containing spaces. 
    (On Windows, arguments are sent to a program as a single "command-line" string, and programs are responsible for parsing it into arguments. By default, empty arguments and arguments with spaces or tabs are quoted with double quotes " in the command line, and/or " are preceded by backslashes. 
    windows_verbatim=true is useful for launching programs that parse their command line in nonstandard ways.) Has no effect on non-Windows systems.
    
    windows_hide::Bool: If true (defaults to false), then on Windows no new console window is displayed when the Cmd is executed. 
    This has no effect if a console is already open or on non-Windows systems.
    
    env: Set environment variables to use when running the Cmd. 
    env is either a dictionary mapping strings to strings, an array of strings of the form "var=val", an array or tuple of "var"=>val pairs. In order to modify (rather than replace) the existing environment, initialize env with copy(ENV) and then set env["var"]=val as desired. 
    To add to an environment block within a Cmd object without replacing all elements, use addenv() which will return a Cmd object with the updated environment.
    
    dir::AbstractString: Specify a working directory for the command (instead of the current directory).
   """
    ignorestatus::Bool
    windows_verbatim::Bool
    # Arguments of pipeline (https://docs.julialang.org/en/v1/base/base/#Base.pipeline-Tuple{Base.AbstractCmd})
    # Pipes (nothing = default (stdout, stdin, ect))
    # Thoses are callbacks (callables) that take those pipes as arguments
    cb_stdin
    cb_stdout
    cb_stderr
    append::Bool

    function SessionConfig(; 
        ignorestatus = false,
        windows_verbatim = false,
        cb_stdin = nothing,
        cb_stdout = nothing,
        cb_stderr = nothing,
        append = false
        )
        return new(ignorestatus, windows_verbatim, cb_stdin, cb_stdout, cb_stderr, append)
    end
end

function StoringConfig()
    # In a storing config we only capture stdout and stderr
    # We also do not want the submited commands to throw Exception on failure
    function testread(stream::IO)
        while (!eof(stream))
            println(readline(stream))
        end
        return "Toto"
    end
    SessionConfig(;
        ignorestatus = true,
        # Note: this is this read method https://github.com/JuliaLang/julia/blob/d386e40c17d43b79fc89d3e579fc04547241787c/base/io.jl#L520-L524
        #TODO: Populate vector in realtime from the pipe ?
        cb_stdout = x::IO -> split(String(read(x)),'\n'),
        cb_stderr = x::IO -> split(String(read(x)),'\n')
    )
end

"""
    A SilentConfig is a SessionConfig that ignore stdin, stdout and stderr.
    This is useful when your are not interested in the output content of a command
"""
function SilentConfig()
    SessionConfig(;
        cb_stdin =  x::IO -> (),
        cb_stdout = x::IO -> (),
        cb_stderr = x::IO -> ()
    )
end

function __get_pipeline(config::SessionConfig, cmd::Base.AbstractCmd)
    # stream_in
    pstdin = isnothing(config.cb_stdin) ? nothing : Pipe()#IOBuffer #Pipe -> requires close(p.in)
    pstdout = isnothing(config.cb_stdout) ? nothing : Pipe()
    pstderr = isnothing(config.cb_stderr) ? nothing : Pipe()
    return Base.pipeline(
        Base.Cmd(cmd; windows_verbatim = config.windows_verbatim, ignorestatus = config.ignorestatus),
        stdin = pstdin,
        stdout = pstdout,
        stderr = pstderr,
        append = config.append
    ), pstdin, pstdout, pstderr
end
struct LocalSession <: AbstractSession
    # Formatting function to format command before submission
    format_fct::Base.Callable
    pathtype::Type{<:AbstractPath}
    config::SessionConfig
end

format(session::AbstractSession, cmd::Base.AbstractCmd) = session.format_fct(cmd)
"""
    Given a SessionConfig `template_config`, this methods create a new SessionConfig
    based on `template_config` with the appropriate paramenter given the Session type.
    For example, for a LocalSession, windows_verbatim is forced at `true` on windows systems.
"""
function format(::Type{LocalSession}, template_config::SessionConfig)
    return SessionConfig(;
        ignorestatus = template_config.ignorestatus,
        # As we are calling 'bash -c "<cmd>"' on windows systems, we would like to ignore quote added by Julia.Base.Cmd
        windows_verbatim = Sys.iswindows(),
        cb_stdin = template_config.cb_stdin, 
        cb_stdout = template_config.cb_stdout,
        cb_stderr = template_config.cb_stderr,
        append = template_config.append
    )
end

"""
    Returns a callable that can be Launched in a Task.
    To launch sequentially: command(session, cmd)()
    To launch asynchronously: @async command(session, cmd)
"""
function command(session::AbstractSession, cmd::Base.AbstractCmd)
    config = session.config
    pipeline, pstdin, pstdout, pstderr = __get_pipeline(config, format(session, cmd))
    cb = () -> begin
        # Launch command in a process
        process = Base.run(pipeline)
        # Prepare task handling
        tin, tout, terr = nothing, nothing, nothing
        # Close active pipes
        if !isnothing(pstdin) close(pstdin.in) end
        if !isnothing(pstdout) close(pstdout.in) end
        if !isnothing(pstderr) close(pstderr.in) end
        # Asynchronously read from the pipes with async tasks to avoid deadlock 
        if !isnothing(config.cb_stdin) tin = @async config.cb_stdin(pstdin) end
        if !isnothing(config.cb_stdout) tout = @async config.cb_stdout(pstdout) end
        if !isnothing(config.cb_stderr) terr = @async config.cb_stderr(pstderr) end
        # fetch tasks (wait for their terminations and get there return values)
        return process, fetch(tin), fetch(tout), fetch(terr)
    end
    return cb
end

function BashSession(; template_config::SessionConfig = SessionConfig(), type::Type{<:AbstractSession} = LocalSession)
   # Check that the current operating system as the bash program (by default on posix systems)
    if Sys.iswindows()
        format_fct = (c::Base.AbstractCmd) -> Base.Cmd(vcat(["cmd", "/C", "bash", "-c"], "\"", c.exec, "\""))
        silent_session = type(format_fct, WindowsPath, format(type, StoringConfig()))
        # Submit command silently and sequentially
        process, in, out, err = command(silent_session, `ls`)()
        # By now the standart output and errors should be in out and err
        if process.exitcode != 0
            throw(SystemError("Your Windows system does not seem to have 'bash' program installed."))
        end
        # Else return new bash session
        return type(format_fct, WindowsPath, format(type, template_config))
    else
        # If not windows, the command formatting function does nothing to a command.
        # We assume that 'bash' is by default available on those systems.
        return type((c::Base.AbstractCmd) -> c, PosixPath, template_config)
    end

end