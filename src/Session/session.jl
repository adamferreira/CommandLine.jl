

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

# As session.chin is a channel os size 1
# Consecutive calls to `run` is blocking until
function run(cmd::AbstractString, session::BashSession) 
    put!(session.chin, cmd)
end

struct LocalBashSession <: BashSession
    pwd
    env

    bashproc::Base.Process
    chin::Base.Channel
    chout::Base.Channel
    cherr::Base.Channel

    task_out::Task
    task_err::Task

    function LocalBashSession(; pwd = Base.pwd(), env = nothing)
        bashcmd::Base.Cmd = Sys.iswindows() ? `cmd /C bash` : `bash`
        # Launch the internal bash process in the background
        bashproc, chin, chout, cherr = run_background(bashcmd;
            windows_verbatim = Sys.iswindows(),
            windows_hide = false,
            dir = string(pwd),
            env = env,
        )

        # Launch stream handling tasks
        task_out = realtime_readlines(chout, x -> println(x))
        task_err = realtime_readlines(cherr, x -> println(x))

        return new(pwd, env, bashproc, chin, chout, cherr, task_out, task_err)
    end
end

function close(session::LocalBashSession)
    # Send the exit signal to the bash process
    run("exit", session)
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
end

l = LocalBashSession()
run("ls && sleep 5", l)
run("ls", l)
close(l)