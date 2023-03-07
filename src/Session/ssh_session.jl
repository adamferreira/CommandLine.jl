

mutable struct RemoteSSHSession <: CommandLine.AbstractBashSession 
    bashsession::CommandLine.BashSession
    username::AbstractString
    hostname::AbstractString
    port::UInt32

    function RemoteSSHSession(username, hostname, port; pwd = "~", env = nothing)
        bashcmd::Base.Cmd = `ssh -t $(username)@$(hostname) -p $(port) -A -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -oLogLevel=ERROR`
        return new(
            CommandLine.BashSession(bashcmd; pwd=pwd, env=env),
            username,
            hostname,
            port
        )
    end
end

# Forward session so it can be used the same as a BashSession
CommandLine.bashsession(s::RemoteSSHSession) = s.bashsession
CommandLine.iswindows(s::RemoteSSHSession)::Bool = false

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