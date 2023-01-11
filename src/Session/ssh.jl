struct RemoteSSHSession <: AbstractSession 
    username::AbstractString
    hostname::AbstractString

    # No explicit typing as we want to handle all path-like types.
    # string(pwd) must be defined
    pwd
    # environment variables
    env
end

function format(session::RemoteSSHSession, cmd::Base.AbstractCmd)
    return Base.Cmd(vcat(["cd $(pwd(session))", "&&", "ssh"], "\"", collect(cmd), "\""))
end