

mutable struct RemoteSSHSession <: BashSession 
    # --- Base BashSession arguments ---
    # environment variables
    env
    # Bashgroung SSH process
    bashproc::Base.Process
    # Communication streams to the background process
    instream::Base.Pipe
    outstream::Base.BufferStream
    errstream::Base.BufferStream
    # Mutex (TODO: remove ?)
    run_mutex::Base.Threads.Condition

    # --- Specific RemoteSSHSession arguments ---
    username::AbstractString
    hostname::AbstractString
    port::UInt32

    function RemoteSSHSession2(username, hostname, port; pwd = "~", env = nothing)
        # Launch the internal SSH process in the background
        bashproc, instream, outstream, errstream = CommandLine.run_background(
            `ssh -t $(username)@$(hostname) -p $(port) -A -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -oLogLevel=ERROR`;
            windows_verbatim = Sys.iswindows(),
            windows_hide = false,
            dir = Base.pwd(), # This is a local dir here
            env = env,
        )
        
        if !process_running(bashproc)
            @error "ssh -t $(username)@$(hostname) -p $(port) -A -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o LogLevel=ERROR"
            throw(SystemError("Cannot start the SSH process", bashproc.exitcode))
        end

        s = new(username, hostname, port, env, bashproc, instream, outstream, errstream, Base.Threads.Condition())
        if !CommandLine.isdir(s, pwd)
            throw(SystemError("Cannot find path pwd=$(pwd) on remote machine", -1))
        end

        # Define destructor for RemoteSSHSession (exiting the background bash program)
        # This will be called by the GC
        # DEFAULT_SESSION will be closed when exiting Julia
        finalizer(CommandLine.close, s)
        return s
    end

    # This Constructor is necessary for BashSessionCstr to correctly instantiate the object
    function RemoteSSHSession(arg...)
        return new(arg...)
    end

    function RemoteSSHSession(username, hostname, port; pwd = "~", env = nothing)
        bashcmd::Base.Cmd = `ssh -t $(username)@$(hostname) -p $(port) -A -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -oLogLevel=ERROR`
        return BashSessionCstr(RemoteSSHSession, bashcmd, pwd, env, username, hostname, port)
    end
end

function upload_command(s::RemoteSSHSession, srcs::AbstractString, dest::AbstractString; silent::Bool = true)::String
    flags = ""
    if silent
        flags = "-oLogLevel=ERROR -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no"
    end
    # Quotes if "src" is several files space separated
    return "scp $(flags) -P $(s.port) $(srcs) $(s.username)@$(s.hostname):$(dest)"
end


function download_command(s::RemoteSSHSession, srcs::AbstractString, dest::AbstractString; silent::Bool = true)::String
    flags = ""
    if silent
        flags = "-oLogLevel=ERROR -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no"
    end
    # Quotes if "src" is several files space separated
    return "scp $(flags) -P $(s.port) $(s.username)@$(s.hostname):\"$(srcs)\" $(dest)"
end