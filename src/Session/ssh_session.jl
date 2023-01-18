

mutable struct RemoteSSHSession <: BashSession 
    # SSH configuration
    username::AbstractString
    hostname::AbstractString
    port::UInt32
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

    function RemoteSSHSession(username, hostname, port; pwd = "~", env = nothing)
        # Launch the internal SSH process in the background
        bashproc, instream, outstream, errstream = CommandLine.run_background(
            `ssh -t $(username)@$(hostname) -p $(port) -A -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -o LogLevel=ERROR`;
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
        if !isdir(pwd, s)
            throw(SystemError("Cannot find path pwd=$(pwd) on remote machine", -1))
        end

        # Define destructor for RemoteSSHSession (exiting the background bash program)
        # This will be called by the GC
        # DEFAULT_SESSION will be closed when exiting Julia
        finalizer(CommandLine.close, s)
        return s
    end
end
