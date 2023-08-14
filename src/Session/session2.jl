# Transform a command to its instanciated string
cmdstr(cmd::Base.Cmd) = join(cmd.exec," ")

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
    Shell Type `ST` (Bash, shell, Powershell, ...)
"""
abstract type ShellType end
abstract type Shell <: ShellType end # sh
abstract type Bash <: ShellType end


"""
    Connection Type `CT` (Local, SSH, ...)
"""
abstract type ConnectionType end
abstract type Local <: ConnectionType end
abstract type SSH <: ConnectionType end

mutable struct Session{ST <: ShellType, CT <: ConnectionType} <: AbstractSession
    # Underlying command used to start `proc`
    cmd::Base.Cmd
    # environment variables
    env::Dict{String,String}
    # Underlying interpretor (Shell,...) process
    interproc::Base.Process
    # Communication streams to the background process
    instream::Base.Pipe
    outstream::Base.BufferStream
    errstream::Base.BufferStream
    # Mutex to avoid colision en stream when session are used asynchronously
    run_mutex::Base.Threads.Condition

    # Default (Generic) constructor
    function Session{ST,CT}(cmd::Base.Cmd; pwd = Base.pwd(), env = nothing) where {ST <: ShellType, CT <: ConnectionType}
        # Launch the internal process in the background
        interproc, instream, outstream, errstream = run_background(
            cmd;
            windows_verbatim = Sys.iswindows(),
            windows_hide = false,
            dir = Base.pwd(), # This is a local dir here
            env = env,
        )

        # Check that the internal process is running
        if !process_running(interproc)
            throw(SystemError("Cannot start the bash process $(cmd)", interproc.exitcode))
        end

        # Create the Session object around the background process
        s = new{ST,CT}(
            cmd,
            isnothing(env) ? Dict{String,String}() : env,
            interproc,
            instream,
            outstream,
            errstream,
            Base.Threads.Condition()
        )

        # Activate custom working directory
        # May throw if the path does not exist
        #cd(s, pwd)

        # Define destructor for all Session subtypes (exiting the background bash program)
        # This will be called by the GC
        # DEFAULT_SESSION will be closed when exiting Julia
        finalizer(close, s)
    end
end

"""
    run(session::BashSession, cmd::AbstractString; newline_out::Function, newline_err::Function) -> Int64
    * `session` bash session
    * `cmd` Command to be launched in the bash session
    * `newline_out::Union{Function, Nothing}`: Callback that will be called for each new `stdout` lines created by the separate process.
    * `newline_err::Union{Function, Nothing}`: Callback that will be called for each new `stderr` lines created by the separate process.
Run the `cmd` command in the active bash session.
This method is blocking and will return as soon a the command finished (success or error).
Return the status of the launched command (given by bash variable `\$?`).
"""
function run(session::Session, cmd::Base.Cmd; newline_out::Function, newline_err::Function)
    # Lock this method
    lock(session.run_mutex)

    # Check if the background process is alive
    if !isopen(session)
        @error "Session is closed"
        unlock(session.run_mutex)
        return
    end

    # Get current process hash to personnalize the `done` signal so it does not enter in conflics with normal error logs
    t_uuid = current_task().rngState0

    # Begin the async master task to handle both stdout and stderr of the background bash process
    master_task = @async begin
        # Channel to communicate between the two subtasks (handle stdout and handle stderr)
        ch_done = Channel(1)

        # Launch stdout handle subtask
        task_out = @async begin
            while Base.isopen(ch_done)
                # Blocks until a entry is avaible in the channel
                # Takes the entry and unlock the channel to be filled again
                out = String(readavailable(session.outstream))
                for l in split(out, '\n')
                    if length(l) == 0 continue; end
                    newline_out(l)
                end
            end
        end

        # Launch stderr handle subtask
        task_err = @async begin
            done = false
            status = "-1"
            while !done
                # Blocks until a entry is avaible in the channel
                # Takes the entry and unlock the channel to be filled again
                out = String(readavailable(session.errstream))
                for l in split(out, '\n')
                    if length(l) == 0 continue; end
                    # TODO: Optimize 
                    if occursin("done $(t_uuid)" , l)
                        done = true
                        # Extract the command status from `done` signal
                        r = findfirst("done $(t_uuid)" , l)
                        status = l[r.stop+2:end]
                    else 
                        newline_err(l)
                    end
                end

            end
            # Close the channel to notify `task_out` that it can stop the scrapping
            Base.close(ch_done)
            return Base.parse(Int64, status)
        end

        # Wait for the `done` signal from `cmd` 
        status = fetch(task_err)
        # Now `task_err` is finished and `ch_done` is closed
        # But `task_out` might get stuck in `readavailable` is now events appears in stdout anymore
        # Trigger an output in stdout so that `task_out` detects the channel as closed
        write(session.instream, "echo" * "\n")
        # Wait for the trigger to be processed
        wait(task_out)
        # The handling of stdout and stderr is now over !
        # Return the status of the command
        return status
    end

    # Submit commmand to the process's instream via the Channel
    # Alter the command with a "done" signal that also contains taskid and the previous command return code (given by `$?` in bash)
    # As `cmd` and `echo done <taskid>` are two separate commands, `$?` gives back the return code of `cmd`
    write(session.instream, cmdstr(cmd) * " ; echo \"done $(t_uuid) \$?\" 1>&2" * "\n")
    
    # Wait for the master task to finish 
    # this means stderr handling found the `done` signal and stdout handling stoped because the channel between them was closed
    status = fetch(master_task)
    unlock(session.run_mutex)
    # Return the status of the command
    return status
end

"""
    `close(session::Session)`
Closes `session` by sending the `exit` signal to its internal process `interproc`.
This method is blocking.
"""
function close(session::Session)
    lock(session.run_mutex)
    # Send the exit signal to the bash process (Do not call `run` here as we will never get the `done` signal)
    # TODO: exit is only valid for Shell session; we should support other closing commands !!!
    write(session.instream, "exit \n")
    # Buffering to make sure the process as processed all its inputs in instream and as finished normally
    # TODO: optimize ?
    while process_running(session.interproc)
        sleep(0.05)
    end
    # Wait for the process to finish (it should have processed the exist signal)
    # Finishing the process closes its streams (in, out, err) and thus finished the treating task binded to the channels (instream, outstream, errstream)
    wait(session.interproc)
    #close(session.instream); close(session.outstream); close(session.errstream);
    # session.task_out and session.task_err will termiate as session.outstream and session.errstream are now closed
    @assert !isopen(session.outstream)
    @assert !isopen(session.errstream)
    unlock(session.run_mutex)
end


isopen(session::Session) = Base.process_running(session.interproc)

# Specific constructors for each combination of ShellType and ConnectionType

function Session{Bash, CT}(; pwd = "~", env = nothing) where {CT<:ConnectionType}
    bashcmd::Base.Cmd = Sys.iswindows() ? `cmd /C bash` : `bash`
    return Session{Bash,CT}(bashcmd; pwd=pwd, env=env)
end

# Type aliasing
LocalBashSession = Session{Bash, Local}
SSHSession = Session{Bash, SSH}


s = LocalBashSession()
f = x -> println(x)
run(s, `ls .`, newline_out=f,newline_err=f)