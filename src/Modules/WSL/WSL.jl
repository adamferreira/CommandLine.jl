module WSL

import CommandLine.Paths as Paths
import CommandLine as CLI

import CSV as CSV
import DataFrames as DF

mutable struct WSLInstance
    # Custom name of the instance
    name::String
    # (sudo) user on the instance
    user::String
    # Shell running on the host machine/OS
    hostshell::Union{Nothing, CLI.Shell}
    # Workspace where all files will be copied before copying into the running instance, lives on host
    workspace_host::Paths.AbstractPath
    # Workspace, but its posix path as mounted by WSL
    workspace_instance::Paths.PosixPath
    # Filesystem directory for the instance
    # Contains the .vhdx file and other utils used by this package
    fsroot_host::Paths.AbstractPath
    fsroot_instance::Paths.PosixPath

    function WSLInstance(
        name::String,
        user::String,
        filesystem_root::Union{String, Paths.AbstractPath},
        s::CLI.Shell = CLI.GitBash();
    )
        # Create temporary workspace for this app (posix path form)
        wpname = "$(name)_$(Base.hash(name))"
        workspace_host = Paths.pathtype()(Base.joinpath(Base.pwd(), wpname))
        workspace_instance = mounted_path(workspace_host)

        # Get paths for root filesystem
        fsroot_host = Paths.pathtype()("$(filesystem_root)")
        fsroot_instance = mounted_path(fsroot_host)

        wsli = new(name, user, s, workspace_host, workspace_instance, fsroot_host, fsroot_instance)
        return wsli
    end
end
export WSLInstance

name(wsli::WSLInstance) = wsli.name
export name
user(wsli::WSLInstance) = wsli.user
export user
hostshell(wsli::WSLInstance) = wsli.hostshell
export hostshell
workspace(wsli::WSLInstance) = wsli.workspace_host
export workspace
workspace_instance(wsli::WSLInstance) = wsli.workspace_instance
export workspace_instance
home(wsli::WSLInstance) = Paths.PosixPath("/home/$(user(wsli))")
export home
cachedir(wsli::WSLInstance) = Paths.joinpath(home(wsli), ".wsljl")
export cachedir
fsroot(wsli::WSLInstance) = wsli.fsroot_host
export fsroot
fsroot_instance(wsli::WSLInstance) = wsli.fsroot_instance
export fsroot_instance

# Get the mounted paths in the instance of a path in the host
function mounted_path(p::Union{String, Paths.AbstractPath})::Paths.PosixPath
    # TODO: Do not convert if input is already a PosixPath
    # TODO: Do not convert if PP[1] is not a drive name
    pp = splitpath("$p")
    # Now transform the first segments <drive>: into /mnt/<drive>
    pp[1] = "/mnt/$(lowercase(pp[1][1]))"
    return Paths.PosixPath(pp...)
end

function run_on_host_interactive(wsli::WSLInstance, cmd)
    run(cmd)
end
export run_on_host_interactive

function run_on_host(wsli::WSLInstance, cmd)
    CLI.run(hostshell(wsli), cmd)
end
export run_on_host

function __run_on_instance(wsli::WSLInstance, cmd; user = "root", dir = "/home")
    # Sanitize arguments to avoid unwanted quotes
    _cmd = map(s -> string(s), split("$(cmd)", ' '))
    _user = map(s -> string(s), split("$(user)", ' '))
    _dir = map(s -> string(s), split("$(dir)", ' '))
    run(
        Cmd([
            "wsl", "--distribution", name(wsli),
            "--user", _user...,
            "--cd", _dir...,
            _cmd...
        ])
    )
    #Base.run(`wsl --distribution $(name(wsli)) --user $(user) $(cmd)`)
end

run_on_instance(wsli::WSLInstance, cmd) = __run_on_instance(wsli, cmd; user = user(wsli), dir = home(wsli))
run_on_instance_as_root(wsli::WSLInstance, cmd) = __run_on_instance(wsli, cmd; user = "root", dir = "/root")
export run_on_instance, run_on_instance_as_root

function clean_workspace(wsli::WSLInstance)
    if isdir(workspace(wsli) |> string)
        @info "Cleaning workspace $(workspace(wsli))"
        rm(workspace(wsli) |> string, recursive = true)
    end
end
export clean_workspace

function create_workspace(wsli::WSLInstance)
    if isdir(hostshell(wsli) |> string)
        clean_workspace(wsli)
    end
    @info "Creating workspace $(workspace(wsli))"
    mkdir(workspace(wsli) |> string)
end
export create_workspace

function list_instances(s::CLI.Shell = CLI.GitBash())::Vector{String}
    out = CLI.checkoutput(s, "wsl --list")
    out = map(l -> replace(l, '\0' => ""), out)
    out = map(l -> replace(l, '\r' => ""), out)
    out = map(l -> replace(l, "(Default)" => ""), out)
    return filter(l -> l != "", out)
end
export list_instances

function running_instances(s::CLI.Shell = CLI.GitBash())::Vector{String}
    out = CLI.checkoutput(s, "wsl --list --running")
    out = map(l -> replace(l, '\0' => ""), out)
    out = map(l -> replace(l, '\r' => ""), out)
    out = map(l -> replace(l, "(Default)" => ""), out)
    return filter(l -> l != "", out)
end
export running_instances

exits(wsli::WSLInstance)::Bool = name(wsli) in list_instances(hostshell(wsli))
export exits
isrunning(wsli::WSLInstance)::Bool = name(wsli) in running_instances(hostshell(wsli))
export isrunning

# TODO: Import already setup wsljl tarballs 
# import

unregister(wsli::WSLInstance) = run_on_host_interactive(wsli, `wsl --unregister $(name(wsli))`)

function import_from_scratch!(
    wsli::WSLInstance;
    local_tarball::Union{Nothing, Paths.AbstractPath} = nothing,
    remote_tarball::Union{Nothing, String} = nothing,
    regenerate_if_exists::Bool = false,
)

    function deploy_from_local_tarball(wsli::WSLInstance, tarball::Paths.AbstractPath)
        # Cleanup
        if exits(wsli) && regenerate_if_exists
            @info "Wipping $(name(wsli))"
            unregister(wsli)
        end
        
        # Check tarball
        if !isfile(tarball |> string)
            throw("Could not find tarball $(tarball)")
        end

        # Setup filesystem root
        if !isdir(fsroot(wsli) |> string)
            try
                mkdir(fsroot(wsli) |> string)
            catch e
                @error "Could not create filesystem root $(fsroot(wsli))"
                throw(e)
            end
        else
            throw("Filesystem Root $(fsroot(wsli)) already exists")
        end

        # Create instance
        @info "Deploying instance $(name(wsli))"
        @debug "from $(tarball) with fs root $(fsroot(wsli))"
        if exits(wsli)
            throw("Instance $(name(wsli)) already exists")
        end
        run_on_host_interactive(wsli, `wsl --import $(name(wsli)) $(fsroot(wsli)) $(tarball)`)

        # Now that the instance is running, setup the user
        # 'sudo' group in Fedora is 'wheel'
        @info "Creating user $(user(wsli))"
        p = joinpath(@__DIR__, "wsl_instance_setup.sh")
        run_on_instance_as_root(wsli, "bash $(mounted_path(p)) $(user(wsli))")
        # Create user bashrc
        bash_profile = Paths.pathtype()(joinpath(dirname(@__DIR__), "ContainedEnv", "bash_profile"))
        run_on_instance(wsli, "cp $(mounted_path(bash_profile)) $(home(wsli))/.bash_profile")

        @info "Updating package manager"
        run_on_instance(wsli, "sudo apt-get upgrade -y") # --fix-missing
        run_on_instance(wsli, "sudo apt-get update -y")

        pkmg = PkgManager(wsli)
    end

    function deploy_from_remote_tarball(wsli::WSLInstance, url::String)
        tarball = split(url, '/')[end]
        tarballpath = Paths.joinpath(workspace(wsli) |> string, tarball)
        @info "Downloading `$(tarball)`"
        run_on_host_interactive(wsli, `curl $(url) --output $(tarballpath)`)
        deploy_from_local_tarball(wsli, tarballpath)
    end

    try
        create_workspace(wsli)
        if !isnothing(local_tarball) && !isnothing(remote_tarball)
            throw("Can't have value set for both local_tarball and remote_tarball")
        end

        if !isnothing(local_tarball)
            deploy_from_local_tarball(wsli, local_tarball)
        end

        if !isnothing(remote_tarball)
            deploy_from_remote_tarball(wsli, remote_tarball)
        end
    catch e
        # If anything goes wrong, remove everything related to the app
        unregister(wsli)
        rethrow(e)
    finally
        # Destroy temporary workspace now that everything is setup
        clean_workspace(wsli)
    end
end
export import_from_scratch!

# Open session in the instance
enter(wsli::WSLInstance) = run_on_host_interactive(wsli, `wsl --distribution $(name(wsli)) --user $(user(wsli)) --cd $(home(wsli))`)
export enter











struct Package
    name::String
    version::VersionNumber
    on_install::Union{Nothing, Function}
    on_update::Union{Nothing, Function}
    on_delete::Union{Nothing, Function}
    dependencies

    function Package(
        name::String,
        version::VersionNumber;
        requires = [],
        on_install::Union{Nothing, Function} = nothing,
        on_update::Union{Nothing, Function} = nothing,
        on_delete::Union{Nothing, Function} = nothing,
    )
        return new(name, version, on_install, on_update, on_delete, requires)
    end
end
uid(p::Package)::String = "$(Base.hash(p.name))__$(Base.hash(p.version))"

mutable struct PkgManager
    # Pointer to the WSL instance this Package Manager oversees
    wsli::WSLInstance
    store::DF.DataFrame

    function PkgManager(wsli::WSLInstance)
        pkmg = new(wsli, DF.DataFrame())
        # Load pkg store file (create it if it doesn't exits)
        if !isfile(storefile(pkmg) |> string)
            touch(storefile(pkmg) |> string)
        else
            pkmg.store = DF.DataFrame(CSV.File(storefile(pkmg) |> string))
        end
        return pkmg
    end
end

# Where all packages data are stored on the instance
storedir(pkmg::PkgManager) = Paths.joinpath(cachedir(pkmg.wsli), "packages")
# CSV that stores, for each packages, their detailed information
storefile(pkmg::PkgManager) = Paths.joinpath(storedir(pkmg), "packages.csv")
# For a given package, gives the path to its data folder
pkg_datadir(pkmg::PkgManager, p::Package) = Paths.joinpath(storedir(pkmg), uid(p))
# Files used to install, update, or delete a package
pkg_install_file(pkmg::PkgManager, p::Package) = Paths.joinpath(pkg_datadir(pkmg, p), "install.sh")
pkg_update_file(pkmg::PkgManager, p::Package) = Paths.joinpath(pkg_datadir(pkmg, p), "update.sh")
pkg_delete_file(pkmg::PkgManager, p::Package) = Paths.joinpath(pkg_datadir(pkmg, p), "delete.sh")


end # Module WSL