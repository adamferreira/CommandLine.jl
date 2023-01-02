
abstract type AbstractSession end
mutable struct LocalSession <: AbstractSession
    # Formatting function to format command before submission
    # for example 'ls' on windows using bash will be 'cmd /C bash -c ls'
    cmd_decorator::Function
    pathtype::Type{<:AbstractPath}
end
format(session::AbstractSession, cmd::Base.AbstractCmd) = session.cmd_decorator(cmd)
iswindows(::LocalSession) = Sys.iswindows()

"""
function async_reader(io::IO, timeout_sec)::Channel
    ch = Channel(1)
    task = @async begin
        reader_task = current_task()
        function timeout_cb(timer)
            put!(ch, :timeout)
            Base.throwto(reader_task, InterruptException())
        end
        timeout = Timer(timeout_cb, timeout_sec)
        data = String(readavailable(io))
        if data == ""; put!(ch, :eof); return; end
        timeout_sec > 0 && close(timeout) # Cancel the timeout
        put!(ch, data)
    end
    bind(ch, task)
    return ch
end
"""

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

Run a `Cmd` object.

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

# TODO: comment usage of new_in, new_out, new_err
function run(
    cmd::Base.AbstractCmd;
    windows_verbatim::Bool = false,
    windows_hide::Bool = false,
    dir::AbstractString = "",
    env = nothing,
    new_in::Union{Function, Nothing} = nothing,
    new_out::Union{Function, Nothing} = nothing,
    new_err::Union{Function, Nothing} = nothing
)

    # Open the different communication pipes
    pipe_in = isnothing(new_in) ? nothing : Base.BufferStream()
    pipe_out = isnothing(new_out) ? nothing : Base.BufferStream()
    pipe_err = isnothing(new_err) ? nothing : Base.BufferStream()

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
    task_out = isnothing(new_out) ? nothing : @async realtime_read(pipe_out, String; newentry = new_out)
    task_err = isnothing(new_err) ? nothing : @async realtime_read(pipe_err, String; newentry = new_err)

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
    session::AbstractSession,
    cmd::Base.AbstractCmd;
    new_in::Union{Function, Nothing} = nothing,
    new_out::Union{Function, Nothing} = nothing,
    new_err::Union{Function, Nothing} = nothing
)
    run(
        format(session, cmd);
        windows_verbatim = iswindows(session),
        windows_hide = false,
        new_in = new_in,
        new_out = new_out,
        new_err = new_err
    )
end


function local_bash_session()
    # Check that the current operating system as the bash program (by default on posix systems)
    # To do that we create a temporary local session
   if Sys.iswindows()
        format_fct = (c::Base.AbstractCmd) -> Base.Cmd(vcat(["cmd", "/C", "bash", "-c"], "\"", collect(c), "\""))
        local_session = LocalSession(format_fct, WindowsPath)
        process = run(local_session, `ls`)
        if process.exitcode != 0
            @show in, out, err
            throw(SystemError("Your Windows system does not seem to have 'bash' program installed (error code $(process.exitcode))."))
        end
        # Else return new bash session
        return LocalSession(format_fct, WindowsPath)
    else
        # If not windows, the command formatting function does nothing to a command.
        # We assume that 'bash' is by default available on those systems.
        return LocalSession((c::Base.AbstractCmd) -> c, PosixPath)
    end
end