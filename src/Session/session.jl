

function run_background(
    cmd::Base.AbstractCmd;
    windows_verbatim::Bool = false,
    windows_hide::Bool = false,
    dir::AbstractString = "",
    env = nothing
)
    function realtime_read(ostream::IO; T::Type = String)
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
        bind(ch, task_read)
        # Return the binded Channel, the Channel and the task now share the same lifetime
        return ch
    end

    function realtime_write(istream::IO)
        # Open a Channel that can only store one entry at a given time
        ch = Channel(1)
        # Read the channel asynchronously (one entry at a time) and call `newentry` on every entry
        task_treat = @async begin
            while isopen(istream)
                # Blocks until a entry is avaible in the channel
                # Takes the entry and unlock the channel to be filled again
                taken = take!(ch)
                # Submit the command (\n is needed otherwise multiple commands are joined)
                write(istream, taken*"\n")
            end
        end
        Base.bind(ch, task_treat)
        # Return the binded Channel, the Channel and the task now share the same lifetime
        return ch
    end

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
    ch_out = realtime_read(pipe_out)
    ch_err = realtime_read(pipe_err)
    ch_in = realtime_write(pipe_in)

    return process, ch_in, ch_out, ch_err
end


function run_background2(
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

function realtime_readlines(ochan::Channel, newline_callback::Union{Function, Nothing})
    if isnothing(newline_callback) return nothing; end
    return @async begin
        while isopen(ochan)
            # Blocks until a entry is avaible in the channel
            # Takes the entry and unlock the channel to be filled again
            out = take!(ochan)
            # Apply `newline_callback` for each line found in the Channel entry
            for l in split(out, '\n')
                newline_callback(l)
            end
        end
    end
    # Note, this task will finish whenever `ochan` is closed
end


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
* `newline_out::Union{Function, Nothing}`: Callback that will be called for each new `stdout` lines created by the separate process.
* `newline_err::Union{Function, Nothing}`: Callback that will be called for each new `stderr` lines created by the separate process.

For any keywords that are not specified, the current settings from `cmd` are used. Normally,
to create a `Cmd` object in the first place, one uses backticks, e.g.
"""
function run(
    cmd::Base.AbstractCmd;
    windows_verbatim::Bool = false,
    windows_hide::Bool = false,
    dir::AbstractString = "",
    env = nothing,
    newline_out::Union{Function, Nothing} = nothing,
    newline_err::Union{Function, Nothing} = nothing
)
    # Launch the process in the background
    proc, chin, chout, cherr = run_background(cmd;
        windows_verbatim = windows_verbatim,
        windows_hide = windows_hide,
        dir = dir,
        env = env
    )

    task_in = nothing # Not needed here
    task_out = realtime_readlines(chout, newline_out)
    task_err = realtime_readlines(cherr, newline_err)

    # Wait for the process to finish
    wait(proc)
    # Wait for the handling tasks to finish
    fetch(task_in); fetch(task_out); fetch(task_err)

    return proc
end


"""
Should define
* `iswindows(::AbstractSession)`
* `pwd(::AbstractSession)`; `string(pwd(s))` must be defined
* `env(::AbstractSession)`
* `open(::AbstractSession)`
* `newline_out(::Union{Function, Nothing})`
* `newline_err(::Union{Function, Nothing})`
"""
abstract type AbstractSession end
abstract type BashSession <: AbstractSession end


# TODO : Make atomic
# TODO : give ostream callbacks here
"""
function run2(cmd::AbstractString, session::BashSession)
    # TODO : affect an id to the command
    # An look for "task <id> done in the log"
    done = false
    
    File Descriptor	 Abbreviation	Description
    0	STDIN	Standard Input
    1	STDOUT	Standard Output
    2	STDERR	Standard Error
    
    put!(session.chin, cmd * "; (or ||) echo done 1>&2") # Redirect the echo to the program's stderr (more efficient to scrap than stdout)
    t = @async begin
        while !done:
            # if done detected:
            # add a third call back to look for completions
            data = take!(session.chout)
            if data == "task <id> done"
                done = true
            else
                out_callback(data)
    end
end
"""


"""
    ``
Run the `cmd` command in the active bash session.
This method is blocking and will return as soon a the command finished (success or error).
"""
function run(cmd::AbstractString, session::BashSession; newline_out::Union{Function, Nothing} = x -> println("INFO: ", x), newline_err::Union{Function, Nothing} = x -> println("ERROR: ", x))
    # Lock this methos
    lock(session.run_mutex)

    # Begin the async master task to handle both stdout and stderr of the background bash process
    master_task = @async begin
        # Channel to communicate between the two subtasks (handle stdout and handle stderr)
        ch_done = Channel(1)

        # Launch stdout handle subtask
        task_out = @async begin
            while isopen(ch_done)
                # Blocks until a entry is avaible in the channel
                # Takes the entry and unlock the channel to be filled again
                out = String(readavailable(session.chout))
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
                out = String(readavailable(session.cherr))
                for l in split(out, '\n')
                    if length(l) == 0 continue; end
                    # TODO: Optimize 
                    if l == "done" 
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
        write(session.chin, "echo" * "\n")
        # Wiat for the trigger to be processed
        wait(task_out)
        # The handling of stdout and stderr is now over !
    end

    # Submit commmand to the process's instream via the Channel
    # Alter the command with a "done" signal
    write(session.chin, cmd * " && echo done 1>&2" * "\n")
    
    # Wait for the master task to finish 
    # this means stderr handling found the `done` signal and stdout handling stoped because the channel between them was closed
    wait(master_task)
    unlock(session.run_mutex)
end

struct LocalBashSession <: BashSession
    pwd
    env

    bashproc::Base.Process
    chin
    chout
    cherr
    run_mutex::Base.Threads.Condition

    function LocalBashSession(; pwd = Base.pwd(), env = nothing)
        bashcmd::Base.Cmd = Sys.iswindows() ? `cmd /C bash` : `bash`
        # Launch the internal bash process in the background
        bashproc, chin, chout, cherr = run_background2(bashcmd;
            windows_verbatim = Sys.iswindows(),
            windows_hide = false,
            dir = string(pwd),
            env = env,
        )

        return new(pwd, env, bashproc, chin, chout, cherr, Base.Threads.Condition())
    end
end

function close(session::LocalBashSession)
    lock(session.run_mutex)
    println("Calling close")
    # Send the exit signal to the bash process (Do not call `run` here as we will never get the `done` signal)
    write(session.chin, "exit \n")
    # Buffering to make sure the process as process all its input in instream and as finished normally
    while process_running(session.bashproc)
        sleep(0.05)
    end
    # Wait for the process to finish (it should have processed the exist signal)
    # Finishing the process closes its streams (in, out, err) and thus finished the treating task binded to the channels (chin, chout, cherr)
    wait(session.bashproc)
    # session.task_out and session.task_err will termiate as session.chout and session.cherr are now closed
    @assert !isopen(session.chout)
    @assert !isopen(session.cherr)
    unlock(session.run_mutex)
end

@time l = LocalBashSession()
@time run("ls", l)
println("Cmd 1 over")
@time run("ls", l)
close(l)