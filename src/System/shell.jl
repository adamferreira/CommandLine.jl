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
    dir::String = Base.pwd(),
    env::Dict{String,String} = copy(ENV),
    windows_verbatim::Bool = Sys.iswindows(),
    windows_hide::Bool = true
)::Base.Process
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
            # Do not detach as this method `run` can be wrapped in a Task
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
    # Set Process IO's as being the one we just openned
    process.in = pipe_in
    process.out = pipe_out
    process.err = pipe_err
    return process
end

"""
    Shell Interface
Should define:
"""
abstract type AbstractShell end

"""
    Shell Type `ST` (Bash, shell, Powershell, ...)
"""
abstract type ShellType end
abstract type Sh <: ShellType end # sh
abstract type Bash <: ShellType end
abstract type PowerShell <: ShellType end # Broken !
abstract type MySys <: ShellType end # TODO


"""
    Connection Type `CT` (Local, SSH, ...)
"""
abstract type ConnectionType end
abstract type Local <: ConnectionType end
abstract type SSH <: ConnectionType end
abstract type Container <: ConnectionType end

mutable struct Shell{ST <: ShellType, CT <: ConnectionType} <: AbstractShell
    # Underlying command used to start `proc`
    cmd::Base.Cmd
    # environment variables
    env::Dict{String,String}
    # Underlying interpretor (Bash,...) process
    interproc::Base.Process
    # Mutex to avoid colision en stream when session are used asynchronously
    run_mutex::Base.Threads.Condition
    # Default function to use when invoking `run(::Shell, cmd)`
    # This function should take (::Shell, ::Union{Base.Cmd, String}) as arguments
    handler::Function

    # Default (Generic) constructor
    # TODO: Empty ENV by default ?
    function Shell{ST,CT}(cmd::Base.Cmd; pwd = "~", env = copy(ENV), handler::Function = showoutput) where {ST <: ShellType, CT <: ConnectionType}
        # Launch the internal process in the background
        interproc = run_background(
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

        # Create the Shell object around the background process
        s = new{ST,CT}(
            cmd,
            isnothing(env) ? Dict{String,String}() : env,
            interproc,
            Base.Threads.Condition(),
            handler
        )

        # Activate custom working directory
        # May throw if the path does not exist
        cd(s, pwd)

        # Define destructor for all Shell subtypes (exiting the background bash program)
        # This will be called by the GC
        # DEFAULT_SESSION will be closed when exiting Julia
        #finalizer(close, s)
        return s
    end
end

# Access Types
shell_type(s::Shell{ST,CT}) where {ST<:ShellType, CT<:ConnectionType} = ST
connection_type(s::Shell{ST,CT}) where {ST<:ShellType, CT<:ConnectionType} = CT


# Stream access (set by run_background)
instream(s::Shell)::IO = s.interproc.in
outstream(s::Shell)::IO = s.interproc.out
errstream(s::Shell)::IO = s.interproc.err

# Transform a command to its instanciated string
cmdstr(cmd::Base.Cmd) = join(cmd.exec," ")
# Stirng specilization for generic call of `cmdstr` is `run`
cmdstr(cmd::String) = cmd
# Get the last command return code
@inline last_cmd_status_str(s::Shell{PowerShell,CT}) where {CT <: ConnectionType} = "\$?"
@inline last_cmd_status_str(s::Shell{Sh,CT}) where {CT <: ConnectionType} = "\$?"
@inline last_cmd_status_str(s::Shell{Bash,CT}) where {CT <: ConnectionType} = "\$?"
# Command to redirect a command's standart output to the error stream
@inline redirect_stderr_str(s::Shell{Sh,CT}) where {CT <: ConnectionType} = "1>&2"
@inline redirect_stderr_str(s::Shell{Bash,CT}) where {CT <: ConnectionType} = "1>&2"
@inline redirect_stderr_str(s::Shell{PowerShell,CT}) where {CT <: ConnectionType} = "1>2"

# TODO: Set pathtypes for each Shell Types

"""
    run(s::Shell, cmd::Union{Base.Cmd, String}; newline_out::Function, newline_err::Function) -> Int64
    * `session` bash session
    * `cmd` Command to be launched in the Shell (using Strings  is faster and induces less memory allocations)
    * `newline_out::Union{Function, Nothing}`: Callback that will be called for each new `stdout` lines created by the separate process.
    * `newline_err::Union{Function, Nothing}`: Callback that will be called for each new `stderr` lines created by the separate process.
Run the `cmd` command in the active Shell `s`.
This method is blocking and will return as soon a the command finished (success or error).
Return the status of the launched command (given by bash variable `\$?`).
"""
function run_with(
    s::Shell,
    cmd::Union{Base.Cmd, String};
    newline_out::Union{Function, Nothing} = nothing,
    newline_err::Union{Function, Nothing} = nothing,
)::Int64

    # Check if the background process is alive
    if !isopen(s)
        @error "Shell is closed"
        return -1
    end

    # Lock this method
    lock(s.run_mutex)

    # Get current process hash to personnalize the `done` signal so it does not enter in conflics with normal error logs
    t_uuid = current_task().rngState0

    # Begin the async master task to handle both stdout and stderr of the background bash process
    master_task = @async begin
        # Channel to communicate between the two subtasks (handle stdout and handle stderr)
        ch_done = Channel(1)

        # Launch stdout handle subtask (only is there is a callback)
        # As s.interproc is a internal process and feeds s.interproc.out in real-termiate
        # We need to read it in real time
        task_out = @async begin
            while Base.isopen(ch_done) && !isnothing(newline_out)
                # Blocks until a entry is avaible in the channel
                # Takes the entry and unlock the channel to be filled again
                # readavailable also empties the content of the stream that it reads from
                out = String(readavailable(outstream(s)))
                for l in split(out, '\n')
                    if length(l) == 0 continue; end
                    newline_out(l)
                end
            end
        end

        # Launch stderr handle subtask (only is there is a callback)
        task_err = @async begin
            done = false
            status = "-1"
            while !done && !isnothing(newline_err)
                # Blocks until a entry is avaible in the channel
                # Takes the entry and unlock the channel to be filled again
                out = String(readavailable(errstream(s)))
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
        write(instream(s), "echo" * "\n")
        # Wait for the trigger to be processed
        wait(task_out)
        # The handling of stdout and stderr is now over !
        # Return the status of the command
        return status
    end

    # Submit commmand to the process's instream via the Channel
    # Alter the command with a "done" signal that also contains taskid and the previous command return code (given by `$?` in bash)
    # As `cmd` and `echo done <taskid>` are two separate commands, `$?` gives back the return code of `cmd`
    # Use `1>&2` to redirect the 'done' signe to the error stream (faster than parsing standart stream)
    write(instream(s), cmdstr(cmd) * " ; echo \"done $(t_uuid) $(last_cmd_status_str(s))\" $(redirect_stderr_str(s))" * "\n")
    
    # Wait for the master task to finish 
    # this means stderr handling found the `done` signal and stdout handling stoped because the channel between them was closed
    status = fetch(master_task)
    unlock(s.run_mutex)
    # Return the status of the command
    return status
end

"""
    `run_with` wrapper where only `newline_out` is required.
Erros are parsed and handled a local Exceptions.
"""
function run_with(s::Shell, cmd::Union{Base.Cmd, String}, stdout_cb::Union{Function, Nothing})::Int64
    err::String = ""
    status = CommandLine.run_with(s, cmd;
        newline_out = x -> stdout_cb(x),
        newline_err = x -> err = err * '\n' * x
    )
    (status != 0) && throw(Base.IOError("Error running `$cmd`\n$err", status))
    return status
end

"""
    `run_with` wrapper using `Shell` default stdout handler callback.
Erros are parsed and handled a local Exceptions.
"""
function run(s::Shell, cmd::Union{Base.Cmd, String})::Any
    return s.handler(s, cmd)
end



Base.isopen(s::Shell) = Base.process_running(s.interproc)

"""
    `close(s::Shell)`
Closes `s` by sending the `exit` signal to its internal process `interproc`.
This method is blocking.
"""
function Base.close(s::Shell)
    # Do not `lock(s.run_mutex)` as we want this call to interrupt the shell program
    if !isopen(s)
        return nothing
    end

    close(s.interproc)
    # Finishing the process closes its streams (in, out, err) and thus finished the treating task binded to the channels (instream, outstream, errstream)
    wait(s.interproc)
    close(instream(s)); close(outstream(s)); close(errstream(s));
    @assert !isopen(outstream(s))
    @assert !isopen(errstream(s))
end

"""
    checkoutput(cmd::AbstractString, session::AbstractSession)::Vector{String}
Calls `CommandLine.run` and returns the whole standart output in a Vector of `String`.
If the call fails, the standart err is outputed as a `String` is a raised Exception.
"""
function checkoutput(s::Shell, cmd)
    out = Vector{String}()
    CommandLine.run_with(s, cmd, x -> push!(out, x))
    return out
end

function stringoutput(s::Shell, cmd)::String
    out::String = ""
    CommandLine.run_with(s, cmd, x -> out = out * x)
    return out
end

function nooutput(s::Shell, cmd)
    return CommandLine.run_with(s, cmd, nothing)
end

function showoutput(s::Shell, cmd)
    return CommandLine.run_with(s, cmd, x -> println(x))
end

"""
Define pipe operator on `Shell`.
Calls the command `cmd` inside `s`.
Usage:
    `<cmd>` |> s
"""
Base.:(|>)(cmd, s::Shell) = CommandLine.run(s, cmd)

macro run_str(scmd, sess)
    s = Meta.parse(sess)
    return :(CommandLine.run($s, $scmd))
end

"""
    Define access of environment variables within the Shell as `Dict`-like access
"""
function Base.getindex(s::Shell, key)
    v = stringoutput(s, "echo \${$key}")
    return v == "" ? nothing : v
end
function Base.setindex!(s::Shell, value, key)
    s.env[key] = string(value)
    nooutput(s, "export $key=$value")
end

# TODO: define pathtype for Shell ?

"""
Specific constructors for each combination of ShellType and ConnectionType
"""
# Bash Shell (bash must be available on the machine)
#function Shell{Bash,CT}(; pwd = "~", env = copy(ENV)) where {CT<:ConnectionType}
#    bashcmd::Base.Cmd = Sys.iswindows() ? `cmd /C bash` : `bash`
#    return Shell{Bash,CT}(bashcmd; pwd=pwd, env=env)
#end
#
#function Shell{PowerShell,CT}(; pwd = "~", env = copy(ENV)) where {CT<:ConnectionType}
#    Sys.iswindows() || @error "Can only instanciate PowerShell session in Windows environments"
#    # -NoLogo is to prevent the welcome header from appearing
#    return Shell{PowerShell,CT}(`powershell -NoLogo`; pwd=pwd, env=env)
#
#end

"""
Specific constructors for local shell sessions
"""
function Shell{ST,Local}(shellexe::String; kwargs...) where {ST<:ShellType}
    bashcmd::Base.Cmd = Sys.iswindows() ? `cmd /C \"$(shellexe)\"` : `$(shellexe)`
    return Shell{ST,Local}(bashcmd; kwargs...)
end

function LocalGitBash(; kwargs...)
    if Sys.iswindows()
        return Shell{Bash,Local}("C:/Program Files/Git/bin/bash.exe"; kwargs...)
    else
        error("GitBash Shell is not supported for Linux yet")
    end
end


"""
`Shell` that does nothing but returning the command it has been given.
(usefull to instanciate CommandLine's submodules commands like Docker)
"""


"""
Type aliasing
"""
BashShell = Shell{ST,CT} where {ST<:Union{Sh, Bash}, CT<:ConnectionType}
LocalShell = Shell{ST,Local} where {ST<:ShellType}
SSHShell = Shell{ST,SSH} where {ST<:Union{Sh, Bash}}
LocalBashShell = LocalShell{Bash}


"""
    `indir(body::Function, s::Shell, dir::String; createdir::Bool = false)`
Performs all operations in `body` on Shell `s` inside the directly `dir`.
Arg `createdir` creates `dir` if it does not exist in Shell `s`.
All instructions in `body` are assumed to run sequentially on `s`.
After `body` is called, the Shell `s` goes back to its previous current directly.

    indir(s, "~") do s
        @assert pwd(s) == "~"
    end
"""
function indir(body::Function, s::Shell, dir::String; createdir::Bool = false)
    if !CommandLine.isdir(s, dir) && createdir
        CommandLine.mkdir(s, dir)
    end
    prevddir = CommandLine.pwd(s)
    CommandLine.cd(s, dir)
    try
        body(s)
    finally
        CommandLine.cd(s, prevddir)
    end
end

"""
"""
function Base.copy(s::Shell)
    return typeof(s)(
        s.cmd;
        pwd = pwd(s),
        env = copy(s.env),
        handler = s.handler
    )
end