"""
    run(
        cmd::Base.AbstractCmd;
        windows_verbatim::Bool = false,
        windows_hide::Bool = false,
        dir::AbstractString = "",
        env = nothing,
        newline_out::Union{Function, Nothing} = nothing,
        newline_err::Union{Function, Nothing} = nothing
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

For any keywords that are not specified, the current settings from `cmd` are used. Normally,
to create a `Cmd` object in the first place, one uses backticks, e.g.
"""
function run_background(
    cmd::Base.AbstractCmd;
    windows_verbatim::Bool = false,
    windows_hide::Bool = false,
    dir::AbstractString = "",
    env = nothing
)
    # Open the different communication pipes
    # Reading from a BufferStream blocks until data is available
    pipe_in = Base.Pipe()
    pipe_out = Base.BufferStream()
    pipe_err = Base.BufferStream()

    # Construct the pipeline with our custom pipes
    pipeline = Base.pipeline(
        Base.Cmd(
            cmd; 
            # Do not throw Exception when the process finish with non-zero status code (ignorestatus = true)
            # As we are doing everything asynchronously
            ignorestatus = true,
            # Do not detach as this method `run` can be wrapped in a Yask
            detach = false, 
            windows_verbatim = windows_verbatim,
            windows_hide = windows_hide,
            env = env,
            dir = dir
        ),
        # Redirect standart in, out and err of the new process to the custom pipes
        stdin = pipe_in,
        stdout = pipe_out,
        stderr = pipe_err,
        # Do not append as file redirection is not handled here with this system
        append = false
    )
    # Start the backroung process
    process = Base.run(pipeline; wait = false)

    return process, pipe_in, pipe_out, pipe_err
end

"""
    Session Interface
Should define:
"""
abstract type AbstractSession end

"""
    Session Type `ST` (Shell, Windows, ...)
"""
abstract type SessionType end
abstract type Shell <: SessionType end


"""
    Connection Type `CT` (Local, SSH, ...)
"""
abstract type ConnectionType end
abstract type Local <: ConnectionType end
abstract type SSH <: ConnectionType end

mutable struct Session{ST <: SessionType, CT <: ConnectionType} <: AbstractSession
    # Underlying command used to start `proc`
    cmd::Base.Cmd
    # environment variables
    env::Dict{String,String}
    # Bashground process
    proc::Base.Process
    # Communication streams to the background process
    instream::Base.Pipe
    outstream::Base.BufferStream
    errstream::Base.BufferStream
    # Mutex to avoid colision en stream when session are used asynchronously
    run_mutex::Base.Threads.Condition

    # Default (Generic) constructor
    function Session{ST,CT}(cmd::Base.Cmd; pwd = Base.pwd(), env = nothing) where {ST <: SessionType, CT <: ConnectionType}
        # Launch the internal process in the background
        proc, instream, outstream, errstream = CommandLine.run_background(
            cmd;
            windows_verbatim = Sys.iswindows(),
            windows_hide = false,
            dir = Base.pwd(), # This is a local dir here
            env = env,
        )

        # Check that the internal process is running
        if !process_running(proc)
            throw(SystemError("Cannot start the bash process $(cmd)", proc.exitcode))
        end

        # Create the Session object around the background process
        s = new(cmd, env, proc, instream, outstream, errstream, run_callback, Base.Threads.Condition())

        # Activate custom working directory
        # May throw if the path does not exist
        CommandLine.cd(s, pwd)

        # Define destructor for all Session subtypes (exiting the background bash program)
        # This will be called by the GC
        # DEFAULT_SESSION will be closed when exiting Julia
        finalizer(CommandLine.close, s)
    end
end

"""
    `close(session::Session)`
Closes `session` by sending the `exit` signal to its internal process `proc`.
This method is blocking.
"""
function close(session::Session)
    lock(session.run_mutex)
    # Send the exit signal to the bash process (Do not call `run` here as we will never get the `done` signal)
    # TODO: exit is only valid for Shell session; we should support other closing commands !!!
    write(session.instream, "exit \n")
    # Buffering to make sure the process as processed all its inputs in instream and as finished normally
    # TODO: optimize ?
    while process_running(session.proc)
        sleep(0.05)
    end
    # Wait for the process to finish (it should have processed the exist signal)
    # Finishing the process closes its streams (in, out, err) and thus finished the treating task binded to the channels (instream, outstream, errstream)
    wait(session.proc)
    #close(session.instream); close(session.outstream); close(session.errstream);
    # session.task_out and session.task_err will termiate as session.outstream and session.errstream are now closed
    @assert !isopen(session.outstream)
    @assert !isopen(session.errstream)
    unlock(session.run_mutex)
end


isopen(session::Session) = Base.process_running(session.proc)

# Type aliasing
LocalShellSession = Session{Shell, Local}
SSHSession = Session{Shell, SSH}


s = SSHSession()