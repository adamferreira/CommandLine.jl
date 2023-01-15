
"""
struct RemoteSSHSession <: AbstractSession 
    # SSH configuration
    username::AbstractString
    hostname::AbstractString

    # No explicit typing as we want to handle all path-like types.
    # string(pwd) must be defined
    pwd
    # environment variables
    env

    # Piping
end
"""