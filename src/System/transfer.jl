
function default_ssh_keys()
    return CommandLine.joinpath("~", ".ssh", "id_rsa.pub"), CommandLine.joinpath("~", ".ssh", "id_rsa")
end

function scp1(from::BashSession, to::RemoteSSHSession, from_path::AbstractString, to_path::AbstractString)
    # Running the scp command on the host session (can be local or SSH)
    return CommandLine.showoutput(from, CommandLine.upload_command(to, from_path, to_path))
end

# git ls-tree -r master --name-only

### Upload
function transfer_files(from::BashSession, to::RemoteSSHSession, from_paths::Vector{AbstractString}, to_path::AbstractString)
    return CommandLine.scp(from, to, Base.join(from_paths, ' '), to_path)
end

### Download
function transfer_files(from::RemoteSSHSession, to::BashSession, from_paths::Vector{AbstractString}, to_path::AbstractString)
    return CommandLine.scp(to, from, Base.join(from_paths, ' '), to_path)
end

### Local Move
function transfer_files(from::LocalBashSession, to::LocalBashSession, from_paths, to_path)
    return CommandLine.cp(from, Base.join(from_paths, ' '), to_path)
end