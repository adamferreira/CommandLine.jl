abstract type BashSession <: AbstractSession end

"""
    ``
    * `newline_out::Union{Function, Nothing}`: Callback that will be called for each new `stdout` lines created by the separate process.
    * `newline_err::Union{Function, Nothing}`: Callback that will be called for each new `stderr` lines created by the separate process.
Run the `cmd` command in the active bash session.
This method is blocking and will return as soon a the command finished (success or error).
"""
function run(cmd::AbstractString, session::BashSession; newline_out::Function, newline_err::Function)
    # Lock this methos
    lock(session.run_mutex)

    # Get current process hash to personnalize the `done` signal so it does not enter in conflics with normal error logs
    t_uuid = current_task().rngState0

    # Begin the async master task to handle both stdout and stderr of the background bash process
    master_task = @async begin
        # Channel to communicate between the two subtasks (handle stdout and handle stderr)
        ch_done = Channel(1)

        # Launch stdout handle subtask
        task_out = @async begin
            while isopen(ch_done)
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
            while !done
                # Blocks until a entry is avaible in the channel
                # Takes the entry and unlock the channel to be filled again
                out = String(readavailable(session.errstream))
                for l in split(out, '\n')
                    if length(l) == 0 continue; end
                    # TODO: Optimize 
                    if l == "done $(t_uuid)" 
                        done = true
                    else 
                        newline_err(l)
                    end
                end

            end
            # Close the channel to notify `task_out` that it can stop the scrapping
            Base.close(ch_done)
        end

        # Wait for the `done` signal from `cmd` 
        wait(task_err)
        # Now `task_err` is finished and `ch_done` is closed
        # But `task_out` might get stuck in `readavailable` is now events appears in stdout anymore
        # Trigger an output in stdout so that `task_out` detects the channel as closed
        write(session.instream, "echo" * "\n")
        # Wiat for the trigger to be processed
        wait(task_out)
        # The handling of stdout and stderr is now over !
    end

    # Submit commmand to the process's instream via the Channel
    # Alter the command with a "done" signal
    write(session.instream, cmd * " && echo \"done $(t_uuid)\" 1>&2" * "\n")
    
    # Wait for the master task to finish 
    # this means stderr handling found the `done` signal and stdout handling stoped because the channel between them was closed
    wait(master_task)
    unlock(session.run_mutex)
    return 0
end

"""
    `close(session::BashSession)`
Closes the bash session `session` by sending it the `exit` signal.
This method is blocking.
"""
function close(session::BashSession)
    lock(session.run_mutex)
    # Send the exit signal to the bash process (Do not call `run` here as we will never get the `done` signal)
    write(session.instream, "exit \n")
    # Buffering to make sure the process as processed all its inputs in instream and as finished normally
    while process_running(session.bashproc)
        sleep(0.05)
    end
    # Wait for the process to finish (it should have processed the exist signal)
    # Finishing the process closes its streams (in, out, err) and thus finished the treating task binded to the channels (instream, outstream, errstream)
    wait(session.bashproc)
    # session.task_out and session.task_err will termiate as session.outstream and session.errstream are now closed
    @assert !isopen(session.outstream)
    @assert !isopen(session.errstream)
    unlock(session.run_mutex)
end


"""
    checkoutput(session::AbstractSession, cmd::Base.AbstractCmd)
Calls `CommandLine.run` and returns the whole standart output in a `String`.
If the call fails, the standart err is outputed as a `String` is a raised Exception.
"""
function checkoutput(cmd::AbstractString, session::AbstractSession)
    out, err = "", ""
    CommandLine.run(cmd, session;
        newline_out = x -> out = out * x,
        newline_err = x -> err = err * x
    )
    if err != ""
        throw(Base.IOError("$err", -1))
    end

    return out
end


function showoutput(cmd::AbstractString, session::AbstractSession)
    err = ""
    println("$(cmd)")
    CommandLine.run(cmd, session;
        newline_out = x -> println(x),
        newline_err = x -> (print("Error: ",x); err = err * x)
    )
    if err != ""
        throw(Base.IOError("$err", -1))
    end
end


struct LocalBashSession <: BashSession
    pwd
    env
    bashproc::Base.Process
    instream::Base.Pipe
    outstream::Base.BufferStream
    errstream::Base.BufferStream
    run_mutex::Base.Threads.Condition

    function LocalBashSession(; pwd = Base.pwd(), env = nothing)
        bashcmd::Base.Cmd = Sys.iswindows() ? `cmd /C bash` : `bash`
        # Launch the internal bash process in the background
        #TODO Check that bash exist on local system
        bashproc, instream, outstream, errstream = run_background(bashcmd;
            windows_verbatim = Sys.iswindows(),
            windows_hide = false,
            dir = string(pwd),
            env = env,
        )

        # TODO: Check that pwd exists in the bash process filesystem
        return new(pwd, env, bashproc, instream, outstream, errstream, Base.Threads.Condition())
    end
end