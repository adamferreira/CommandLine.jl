
function default_ssh_keys()
    return CommandLine.joinpath("~", ".ssh", "id_rsa.pub"), CommandLine.joinpath("~", ".ssh", "id_rsa")
end

function scp1(from::BashSession, to::BashSession, from_paths::AbstractString, to_dir::AbstractString)
    # Running the scp command on the host session (can be local or SSH)
    cmd = CommandLine.upload_command(to, from_paths, to_dir; silent = false)
    return CommandLine.showoutput(from, cmd)
end

# git ls-tree -r master --name-only

### Upload
function transfer_files(from::BashSession, to::RemoteSSHSession, from_paths::Vector{AbstractString}, to_dir::AbstractString)
    return CommandLine.scp1(from, to, Base.join(from_paths, ' '), to_dir)
end

### Download
function transfer_files(from::RemoteSSHSession, to::BashSession, from_paths::Vector{AbstractString}, to_dir::AbstractString)
    return CommandLine.scp1(to, from, Base.join(from_paths, ' '), to_dir)
end

### Local Move
function transfer_files(from::LocalBashSession, to::LocalBashSession, from_paths, to_dir)
    return CommandLine.cp(from, Base.join(from_paths, ' '), to_dir)
end