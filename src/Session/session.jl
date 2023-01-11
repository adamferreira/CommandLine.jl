
"""
Should define
* `iswindows(::AbstractSession)`
* `pathtype(::AbstractSession)`

# A formatting function to format command before submission
# for example 'ls' on windows using bash will be 'cmd /C bash -c ls'
* `format(session <: AbstractSession, cmd::Base.AbstractCmd)`

* A field `pwd`
* A field `env`
"""
abstract type AbstractSession end
"""
    pwd(session::AbstractSession) -> AbstractPath
Returns the current working directly of the session.
"""
pwd(session::AbstractSession) = session.pwd
env(session::AbstractSession) = session.env

abstract type LocalSession <: AbstractSession end
iswindows(::LocalSession) = Sys.iswindows()

struct LocalBashSession <: LocalSession
    # No explicit typing as we want to handle all path-like types.
    # string(pwd) must be defined
    pwd
    # environment variables
    env

    function LocalBashSession(; pwd = Base.pwd(), check::Bool = true, env = nothing)
        # Create a local bash session
        session = new(pwd, env)
        # Check that the current operating system as the bash program (by default on posix systems)
        if check
            process = CommandLine.run(`ls`, session)
            process.exitcode == 0 || throw(SystemError("Your Windows system does not seem to have 'bash' program installed (error code $(process.exitcode))."))
        end
        return session
    end
end

#posix_cmd(cmd::Base.Cmd) = cmd
#windows_cmd(cmd::Base.Cmd) = `cmd /C $cmd`
#powershell_cmd(cmd::Base.Cmd) = `powershell -Command $cmd`
function format(session::LocalBashSession, cmd::Base.AbstractCmd)
    # On windows bash il called through cmd.exe
    if iswindows(session)
        # TODO: collect will not work with OrCmd and AndCmd (ex: when using pipeline(cmd1, cmd2))
        return Base.Cmd(vcat(["cmd", "/C", "bash", "-c"], "\"", collect(cmd), "\""))
    else
        # If not windows, the command formatting function does nothing to a command.
        # We assume that 'bash' is by default available on those systems.
        return cmd
    end
end

function realtime_read(ostream::IO, T::Type; newentry::Function = x -> x)
    # Open a Channel that can only store one entry at a given time
    ch = Channel(1)
    
    # Read ostream asynchronously and write the entries into the channel one entry at a time
    task_read = @async begin
        while isopen(ostream)
            # As the channel as a size 1, the next put! will be blocked until take!(ch) is called
            # This pause the reading of ostream until the current entry is treated
            put!(ch, T(readavailable(ostream)))
        end
    end

    # Read the channel asynchronously (one entry at a time) and call `newentry` on every entry
    task_treat = @async begin
        while isopen(ch)
            # Blocks until a entry is avaible in the channel
            # Takes the entry and unlock the channel to be filled again
            newentry(take!(ch))
        end
    end
    # Note: Both taks will end when ostream is closed (externally by the process that opened it)
end

"""
    run(
        cmd::Base.AbstractCmd;
        windows_verbatim::Bool = false,
        new_in::Union{Function, Nothing} = nothing,
        new_out::Union{Function, Nothing} = nothing,
        new_err::Union{Function, Nothing} = nothing
    )

Run a `Cmd` object sequentially in a separate process.

* `ignorestatus::Bool`: If `true` (defaults to `false`), then the `Cmd` will not throw an
  error if the return code is nonzero.
* `windows_verbatim::Bool`: If `true` (defaults to `false`), then on Windows the `Cmd` will
  send a command-line string to the process with no quoting or escaping of arguments, even
  arguments containing spaces. (On Windows, arguments are sent to a program as a single
  "command-line" string, and programs are responsible for parsing it into arguments. By
  default, empty arguments and arguments with spaces or tabs are quoted with double quotes
  `"` in the command line, and `\\` or `"` are preceded by backslashes.
  `windows_verbatim=true` is useful for launching programs that parse their command line in
  nonstandard ways.) Has no effect on non-Windows systems.
* `windows_hide::Bool`: If `true` (defaults to `false`), then on Windows no new console
  window is displayed when the `Cmd` is executed. This has no effect if a console is
  already open or on non-Windows systems.
* `env`: Set environment variables to use when running the `Cmd`. `env` is either a
  dictionary mapping strings to strings, an array of strings of the form `"var=val"`, an
  array or tuple of `"var"=>val` pairs. In order to modify (rather than replace) the
  existing environment, initialize `env` with `copy(ENV)` and then set `env["var"]=val` as
  desired.  To add to an environment block within a `Cmd` object without replacing all
  elements, use [`addenv()`](@ref) which will return a `Cmd` object with the updated environment.
* `dir::AbstractString`: Specify a working directory for the command (instead
  of the current directory).
* `handle_instream::Union{Function, Nothing}`: Callback that will be called for each new entry avaible in the separate process `stdin`
* `handle_outstream::Union{Function, Nothing}`: Callback that will be called for each new entry avaible in the separate process `stdout`
* `handle_errstream::Union{Function, Nothing}`: Callback that will be called for each new entry avaible in the separate process `stder`

For any keywords that are not specified, the current settings from `cmd` are used. Normally,
to create a `Cmd` object in the first place, one uses backticks, e.g.
"""
function run(
    cmd::Base.AbstractCmd;
    windows_verbatim::Bool = false,
    windows_hide::Bool = false,
    dir::AbstractString = "",
    env = nothing,
    handle_instream::Union{Function, Nothing} = nothing,
    handle_outstream::Union{Function, Nothing} = nothing,
    handle_errstream::Union{Function, Nothing} = nothing
)

    # Open the different communication pipes
    pipe_in = isnothing(handle_instream) ? nothing : Base.BufferStream()
    pipe_out = isnothing(handle_outstream) ? nothing : Base.BufferStream()
    pipe_err = isnothing(handle_errstream) ? nothing : Base.BufferStream()

    # Construct the pipeline with our custom pipes
    pipeline = Base.pipeline(
        Base.Cmd(
            cmd; 
            # Do not throw Exception with the process finish with non-zero status code (ignorestatus = true)
            # As we are doing everything asynchronously
            ignorestatus = true,
            # Do not detach as this method `run` can be wrapped in a Yask
            detach = false, 
            windows_verbatim = windows_verbatim,
            windows_hide = windows_hide,
            env = env,
            dir = dir
        ),
        # Redirect standart in,out and err of the new process to our custom pipes
        stdin = pipe_in,
        stdout = pipe_out,
        stderr = pipe_err,
        # Do not append as file redirection is not handled here with this system
        append = false
    )

    # Launch the task to handle the pipes (IO) that will be filled by Base.run
    task_in = nothing # Not supported yet
    task_out = isnothing(handle_outstream) ? nothing : @async realtime_read(pipe_out, String; newentry = handle_outstream)
    task_err = isnothing(handle_errstream) ? nothing : @async realtime_read(pipe_err, String; newentry = handle_errstream)

    # Launch the command asynchronously in a separate process
    # Otherwise Base.run will read the whole content of stdout in one go and close the pipes
    process = Base.run(pipeline, wait = false)

    # Wait for the process to finische
    # When over, it will close all the pipes (pipe_in; pipe_out and pipe_err)
    # Thus terminating all the two subtasks of task_in, task_out and task_err
    wait(process)

    # All tasks (task_in, task_out and task_err) are no over from here (and do not return anything)
    # Wait, for good measure !
    fetch(task_in); fetch(task_out); fetch(task_err)

    # Return the launched (and finished) process (usefull to get error code)
    return process
end

function run(
    cmd::Base.AbstractCmd,
    session::AbstractSession;
    handle_instream::Union{Function, Nothing} = nothing,
    handle_outstream::Union{Function, Nothing} = nothing,
    handle_errstream::Union{Function, Nothing} = nothing
)
    CommandLine.run(
        format(session, cmd);
        windows_verbatim = iswindows(session),
        windows_hide = false,
        dir = string(pwd(session)),
        env = env(session),
        handle_instream = handle_instream,
        handle_outstream = handle_outstream,
        handle_errstream = handle_errstream
    )
end

"""
    checkoutput(session::AbstractSession, cmd::Base.AbstractCmd)
Calls `CommandLine.run` and returns the whole standart output in a `String`.
If the call fails, the standart err is outputed as a `String` is a raised Exception.
"""
function checkoutput(cmd::Base.AbstractCmd, session::AbstractSession)
    out, err = "", ""
    process = CommandLine.run(cmd, session;
        handle_outstream = x::String -> out = out * x,
        handle_errstream = x::String -> err = err * x
    )
    if process.exitcode != 0
        throw(Base.IOError("$err", process.exitcode))
    end

    return out
end

function showoutput(cmd::Base.AbstractCmd, session::AbstractSession)
    err = ""
    println("$(cmd)")
    process = CommandLine.run(cmd, session;
        handle_outstream = x::String -> print(x),
        handle_errstream = x::String -> (print(x); err = err * x)
    )
    if process.exitcode != 0
        throw(Base.IOError("$err", process.exitcode))
    end
end