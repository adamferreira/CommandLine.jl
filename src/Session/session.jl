

function __run_background(
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
Should define
* `iswindows(::AbstractSession)`
* `pwd(::AbstractSession)`; `string(pwd(s))` must be defined
* `env(::AbstractSession)`
* `open(::AbstractSession)`
* `close(::AbstractSession)`
"""
abstract type AbstractSession end
abstract type AbstractBashSession <: AbstractSession end

# Default behavior is returning oneself
function bashsession(s::AbstractBashSession)
    return s
end

# Default iswindows checking is done locally
function iswindows(s::AbstractBashSession)::Bool
    return Sys.iswindows()
end

"""
    Clone a session
"""
function clone(s::AbstractBashSession)::AbstractBashSession
    return Nothing
end

"""
    checkoutput(cmd::AbstractString, session::AbstractSession)::Vector{String}
Calls `CommandLine.run` and returns the whole standart output in a Vector of `String`.
If the call fails, the standart err is outputed as a `String` is a raised Exception.
"""
function checkoutput(session::AbstractBashSession, cmd::AbstractString)
    # TODO: Should it throw ?
    out = Vector{String}()
    err = ""
    status = CommandLine.runcmd(
        # Forward session to call runcmd(BashSession)
        bashsession(session),
        cmd;
        newline_out = x -> push!(out, x),
        newline_err = x -> err = err * x
    )
    (status != 0) && throw(Base.IOError("$err", status))
    return out
end

function stringoutput(session::AbstractBashSession, cmd::AbstractString)
    out, err = "", ""
    status = CommandLine.runcmd(
        # Forward session to call runcmd(BashSession)
        bashsession(session),
        cmd;
        newline_out = x -> out = out * x,
        newline_err = x -> err = err * x
    )
    (status != 0) && throw(Base.IOError("$err", status))
    return out
end

function showoutput(session::AbstractBashSession, cmd::AbstractString)
    err = ""
    status = CommandLine.runcmd(
        # Forward session to call runcmd(BashSession)
        bashsession(session),
        cmd;
        newline_out = x -> println(x),
        newline_err = x -> (println("Error: ",x); err = err * x)
    )
    (status != 0) && throw(Base.IOError("$err", status))
end

"""
    Default run behavior
"""
function run(session::AbstractBashSession, cmd::AbstractString)
    return run(bashsession(session), cmd)
end

"""
    `indir(body::Function, session::AbstractBashSession, dir::AbstractString; createdir::Bool = false)`
Performs all operations in `body` on `session` inside the directly `dir`.
Arg `createdir` creates `dir` if it does not exist in `session`.
All instructions in `body` are assumed to run sequentially on `session`.
After `body` is called, the session `session` goes back to its previous current directly.

    indir(session, "~") do s
        @assert pwd(s) == "~"
    end
"""
function indir(body::Function, session::AbstractBashSession, dir::AbstractString; createdir::Bool = false)
    if !isdir(session, dir) && createdir
        mkdir(session, dir)
    end
    @assert isdir(session, dir)
    cd(session, dir)
    try
        body(session)
    finally
        cd(session, "-")
    end
end

struct BashCommand 
    cmd
    session::AbstractBashSession
end

macro run_str(scmd, sess)
    s = Meta.parse(sess)
    return :(CommandLine.run($s, $scmd))
end

macro c_str(scmd, sess)
    s = Meta.parse(sess)
    return :(CommandLine.BashCommand($scmd, $s))
end

"""
Define pipe operator on `AbstractBashSession`.
Calls the command `cmd` inside `session`.
Usage:
    "<cmd>" |> session
"""
Base.:(|>)(cmd::AbstractString, session::AbstractBashSession) = run(session, cmd)

include("bash_session.jl")
include("ssh_session.jl")