
abstract type AbstractSession end

struct SessionConfig
    """
    ignorestatus::Bool: If true (defaults to false), then the Cmd will not throw an error if the return code is nonzero.
    """
    ignorestatus::Bool
    # Arguments of pipeline (https://docs.julialang.org/en/v1/base/base/#Base.pipeline-Tuple{Base.AbstractCmd})
    # Pipes (nothing = default (stdout, stdin, ect))
    stdin
    stdout
    stderr
    append::Bool

    function SessionConfig(; ignorestatus = false, stdin = nothing, stdout = nothing, stderr = nothing, append = false)
        return new(ignorestatus, stdin, stdout, stderr, append)
    end
end

function __get_pipeline(config::SessionConfig, cmd::Base.AbstractCmd)
    #pstdin = isnothing(config.stdin) ? nothing : Pipe()
    return Base.pipeline(
        Base.Cmd(cmd; ignorestatus = config.ignorestatus),
        stdin = config.stdin,
        stdout = config.stdout,
        stderr = config.stderr,
        append = config.append
    )
end

function silent_config()
    # In a silent config we only capture stdout and stderr
    # We also do not want the submited commands to throw Exception on failure
    SessionConfig(
        ignorestatus = true,
        stdin = nothing,
        stdout = Pipe(),
        stderr = Pipe(),
        append = false
    )
end

struct LocalSession <: AbstractSession
    # Prefix command for all commands submitted from this session
    prefix::Base.AbstractCmd
    pathtype::Type{<:AbstractPath}
    config::SessionConfig

    #function LocalSession()
    #    return new(
    #        "",
    #        # Default path is deduced from MacOS
    #        pathtype(),
    #        SessionConfig()
    #    )
    #end
end

function run(session::AbstractSession, cmd::Base.AbstractCmd)
    fullcmd = `$(session.prefix) $(cmd)`
    pipeline = __get_pipeline(session.config, fullcmd)
    return Base.run(pipeline)
end

function bash_session(; config::SessionConfig = SessionConfig(), type::Type{<:AbstractSession} = LocalSession)
   # Check that the current operating system as the bash program (by default on posix systems)
    if Sys.iswindows()
        # Local session to check if the Windows system has a bash program installed
        out = Pipe()
        err = Pipe()
        silent_config = SessionConfig(
            ignorestatus = true,
            stdin = nothing,
            stdout = out,
            stderr = err,
            append = false
        )
        silent_session = type(Base.Cmd(["cmd", "/C", "bash", "-c"]), WindowsPath, silent_config)
        # Run silent process
        process = run(silent_session, `ls`)
        # Close active pipes
        close(out.in)
        close(err.in)
        # Create task to asynchronously read from pipelines
        task_out = @async String(read(out))
        task_err = @async String(read(err))
        # Wait for tasks and get their return values
        lines_out = fetch(task_out)
        lines_err = fetch(task_err)
        println(lines_out)
        println(lines_err)
        if process.exitcode != 0
            throw(SystemError("Your Windows system does not seem to have 'bash' program installed."))
        end
        # Else return new bash session
        return type(Base.Cmd(["cmd", "/C", "bash", "-c"]), WindowsPath, config)
    end

end