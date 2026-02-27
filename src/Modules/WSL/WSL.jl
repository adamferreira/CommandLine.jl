module WSL

import CommandLine.Paths as Paths
import CommandLine as CLI

import CSV as CSV
import DataFrames as DF

# Struct to hold two paths
# One on the host, one on the instance
# Mostly used to copy fro mhost to instance and vice-versa
struct PathBridge
    host::Paths.WindowsPath
    instance::Paths.PosixPath

    function PathBridge(h::Paths.WindowsPath, i::Paths.PosixPath)
        return new(h,i)
    end

    PathBridge(p::Pair{Paths.WindowsPath, Paths.PosixPath}) = PathBridge(p.first, p.second)
end

joinbridge(pb::PathBridge, args...) = PathBridge(Paths.joinpath(pb.host, args...) => Paths.joinpath(pb.instance, args...))

mutable struct WSLInstance
    # Custom name of the instance
    name::String
    # (sudo) user on the instance
    user::String
    # Shell running on the host machine/OS
    hostshell::Union{Nothing, CLI.Shell}
    # Workspace where all files will be copied before copying into the running instance, lives on host
    workspace::Paths.WindowsPath
    # Filesystem directory for the instance
    # Contains the .vhdx file and other utils used by this package
    fsroot_host::Paths.WindowsPath
    # Package manager
    pkmg

    function WSLInstance(
        name::String,
        user::String,
        filesystem_root::Union{String, Paths.WindowsPath},
        s::CLI.Shell = CLI.GitBash();
    )
        # Create temporary workspace for this app (posix path form)
        wpname = "$(name)_$(Base.hash(name))"
        workspace_host = Paths.pathtype()(Base.joinpath(Base.pwd(), wpname))

        # Get paths for root filesystem
        fsroot_host = Paths.pathtype()("$(filesystem_root)")

        wsli = new(name, user, s, workspace_host, fsroot_host, nothing)
        wsli.pkmg = PkgManager(wsli)
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
workspace(wsli::WSLInstance) = wsli.workspace
export workspace
home(wsli::WSLInstance) = Paths.PosixPath("/home/$(user(wsli))")
export home
cachedir(wsli::WSLInstance) = Paths.joinpath(home(wsli), ".wsljl")
export cachedir
fsroot(wsli::WSLInstance) = wsli.fsroot_host
export fsroot

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
    c = [
        "wsl", "--distribution", name(wsli),
        "--user", _user...,
        "--cd", _dir...,
        _cmd...
    ]
    #run_on_host_interactive(wsli, Cmd(c))

    # Will only update the last line in the console
    # This will avoid long output put will still showcase a progress
    CLI.run_with(hostshell(wsli), join(c, " "), x -> print("$(x)\u001b[1000D"))
    # Flush
    println(" \u001b[1000D")
end

run_on_instance(wsli::WSLInstance, cmd) = __run_on_instance(wsli, cmd; user = user(wsli), dir = home(wsli))
run_on_instance_as_root(wsli::WSLInstance, cmd) = __run_on_instance(wsli, cmd; user = "root", dir = "/home")
export run_on_instance, run_on_instance_as_root

copy_to_instance(wsli::WSLInstance, pb::PathBridge) = run_on_instance(wsli, "sudo cp -r $(mounted_path(pb.host)) $(pb.instance)")
copy_to_host(wsli::WSLInstance, pb::PathBridge) = run_on_instance(wsli, "cp -r $(pb.instance) $(mounted_path(pb.host))")


function clean_workspace(wsli::WSLInstance)
    if isdir(workspace(wsli) |> string)
        @warn "Cleaning workspace `$(workspace(wsli))`"
        rm(workspace(wsli) |> string, recursive = true)
    end
end
export clean_workspace

function create_workspace(wsli::WSLInstance)
    if isdir(hostshell(wsli) |> string)
        clean_workspace(wsli)
    end
    @info "Creating workspace `$(workspace(wsli))`"
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
    local_tarball::Union{Nothing, Paths.WindowsPath} = nothing,
    remote_tarball::Union{Nothing, String} = nothing,
    regenerate_if_exists::Bool = false,
)

    function deploy_from_local_tarball(wsli::WSLInstance, tarball::Paths.WindowsPath)
        # Cleanup
        if exits(wsli) && regenerate_if_exists
            @warn "Wipping instance `$(name(wsli))`"
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
        @info "Deploying instance `$(name(wsli))`"
        @debug "from $(tarball) with fs root $(fsroot(wsli))"
        if exits(wsli)
            throw("Instance $(name(wsli)) already exists")
        end
        run_on_host_interactive(wsli, `wsl --import $(name(wsli)) $(fsroot(wsli)) $(tarball)`)

        # Now that the instance is running, setup the user
        # 'sudo' group in Fedora is 'wheel'
        @info "Creating user `$(user(wsli))`"
        p = joinpath(@__DIR__, "wsl_instance_setup.sh")
        run_on_instance_as_root(wsli, "bash $(mounted_path(p)) $(user(wsli))")
        # At this point, custom user exists
        run_on_instance(wsli, "sudo mkdir $(cachedir(wsli))")
        # Create user bashrc
        bash_profile = Paths.pathtype()(joinpath(dirname(@__DIR__), "ContainedEnv", "bash_profile"))
        copy_to_instance(wsli, PathBridge(bash_profile => Paths.joinpath(home(wsli), ".bash_profile")))
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

        instantiate!(wsli.pkmg)
    catch e
        # If anything goes wrong, remove everything related to the app
        if exits(wsli)
            #unregister(wsli)
        end
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
    version::Union{Nothing, VersionNumber}
    on_install::Union{Nothing, Function}
    on_update::Union{Nothing, Function}
    on_delete::Union{Nothing, Function}
    dependencies

    function Package(
        name::String,
        version::Union{Nothing, VersionNumber} = nothing;
        requires = [],
        on_install::Union{Nothing, Function} = nothing,
        on_update::Union{Nothing, Function} = nothing,
        on_delete::Union{Nothing, Function} = nothing,
    )
        return new(name, version, on_install, on_update, on_delete, requires)
    end
end
export Package
name(p::Package) = p.name
version(p::Package) = p.version
versionstr(p::Package) = isnothing(version(p)) ? "default" : "$(version(p))"
uid(p::Package)::String = "$(Base.hash(name(p)))__$(Base.hash(versionstr(p)))"

# Overloads for Set{Package} (colision detection)
Base.hash(p::Package) = Base.hash(Base.hash(name(p)), Base.hash(versionstr(p)))
Base.isequal(a::Package, b::Package) = Base.isequal(Base.hash(a), Base.hash(b))

mutable struct PackageData
    already_on_host::Bool
    already_on_instance::Bool
    should_run_install::Bool
    should_run_update::Bool
    should_run_delete::Bool

    function PackageData()
        return new(false, false, false, false, false)
    end
end

mutable struct PkgManager
    # Pointer to the WSL instance this Package Manager oversees
    wsli::WSLInstance
    store::Dict{Package, PackageData}
    # Packages not yet processed
    packages::Set{Package}
    # Buffer to store current package being processed
    # This means PkgManager can only run sequentially
    current_pkg::Union{Nothing, Package}
    current_pkg_buffer::Vector{String}
    current_pkg_mutex::Base.Threads.Condition

    function PkgManager(wsli::WSLInstance)
        pkmg = new(wsli, Dict{Package, PackageData}(), Set{Package}(), nothing, Vector{String}(), Base.Threads.Condition())
        return pkmg
    end
end
export PkgManager

# Where all packages data are stored on the instance
storedir(pkmg::PkgManager) = PathBridge(Paths.joinpath(workspace(pkmg.wsli), "packages") => Paths.joinpath(cachedir(pkmg.wsli), "packages"))
# CSV that stores, for each packages, their detailed information
storefile(pkmg::PkgManager) = joinbridge(storedir(pkmg), "packages.csv")
# For a given package, gives the path to its data folder
pkg_datadir(pkmg::PkgManager, p::Package) = joinbridge(storedir(pkmg), uid(p))
# Files used to install, update, or delete a package
pkg_data_file(pkmg::PkgManager, p::Package) = joinbridge(pkg_datadir(pkmg, p), "data.json")
pkg_install_file(pkmg::PkgManager, p::Package) = joinbridge(pkg_datadir(pkmg, p), "install.sh")
pkg_update_file(pkmg::PkgManager, p::Package) = joinbridge(pkg_datadir(pkmg, p), "update.sh")
pkg_delete_file(pkmg::PkgManager, p::Package) = joinbridge(pkg_datadir(pkmg, p), "delete.sh")

function RUN(pkmg::PkgManager, cmd::String)
    push!(pkmg.current_pkg_buffer, cmd)
end
RUN(wsli::WSLInstance, p::Package) = RUN(wsli.pkmg, p)

function has_pkg(pkmg::PkgManager, p::Package)
    return haskey(pkmg.store, p)
end

function fetch_pkg_data!(pkmg::PkgManager, p::Package)
    if !has_pkg(pkmg, p)
        dt = PackageData()
        # Trick to see if a package is already on the instance
        # Simply try to fetch its datafile
        try
            # Will throw if datafile does not exist
            run_on_host(pkmg.wsli, "sudo ls $(pkg_data_file(pkmg, p).instance)")
            dt.already_on_instance = true
            dt.should_run_install = false
        catch
            dt.already_on_instance = false
            dt.should_run_install = true
        finally
            pkmg.store[p] = dt
        end
    end

    return pkmg.store[p]
end

function add_pkg!(pkmg::PkgManager, p::Package)
    push!(pkmg.packages, p)
end
add_pkg!(wsli::WSLInstance, p::Package) = add_pkg!(wsli.pkmg, p)

function register_pkg!(pkmg::PkgManager, p::Package)
    # First, add package dependancies
    map(pp -> register_pkg!(pkmg, pp), p.dependencies)

    # Register package to store
    dt = fetch_pkg_data!(pkmg, p)

    # Package already processed, quit
    if dt.already_on_host
        return nothing
    end

    if !dt.already_on_instance
        # Create package cache folder on instance
        run_on_instance(pkmg.wsli, "sudo mkdir -p $(pkg_datadir(pkmg, p).instance)")
    end

    # Create package cache folder on host
    if !isdir(pkg_datadir(pkmg, p).host |> string)
        mkdir(pkg_datadir(pkmg, p).host |> string)
    end

    # Generate `install.sh` of package of host, and send it to the instance
    if !isfile(pkg_install_file(pkmg, p).host |> string)
        touch(pkg_install_file(pkmg, p).host |> string)
    end
    if !isnothing(p.on_install)
        # This will fill `pkmg.current_pkg_buffer`
        lock(pkmg.current_pkg_mutex) do
            pkmg.current_pkg = p
            pkmg.current_pkg_buffer = Vector{String}()
            p.on_install(pkmg)
        end
        # Now, put the content in the package's file
        open(pkg_install_file(pkmg, p).host |> string, "w+") do f
            for line in pkmg.current_pkg_buffer
                write(f, line * "\n")
            end
        end
    end
    copy_to_instance(pkmg.wsli, pkg_install_file(pkmg, p))
    dt.already_on_host = true
    dt.already_on_instance = true
    dt.should_run_install = true


    pkmg.store[p] = dt
    return nothing
end

function install_pkg!(pkmg::PkgManager, p::Package)
    add_pkg!(pkmg, p)

    if !pkmg.store[p].should_run_install
        return nothing
    end

    # Install package dependencies, is needed
    map(pp -> install_pkg!(pkmg, pp), p.dependencies)

    # Install actual package
    @info "Installing package `$(name(p)): $(versionstr(p))`"
    run_on_instance(pkmg.wsli, "sudo bash $(pkg_install_file(pkmg, p).instance)")
    pkmg.store[p].should_run_install = false
    return nothing
end
install_pkg!(wsli::WSLInstance, p::Package) = install_pkg!(wsli.pkmg, p)
export install_pkg!

function instantiate!(pkmg::PkgManager)
    # Local data setup
    if !isdir(storedir(pkmg).host |> string)
        mkdir(storedir(pkmg).host |> string)
    end

    # Get package data
    for p in pkmg.packages
        fetch_pkg_data!(pkmg, p)
    end

    # Host workspace step
    for p in keys(pkmg.store)
        register_pkg!(pkmg, p)
    end

    # Install step
    for p in keys(pkmg.store)
        install_pkg!(pkmg, p)
    end
    # Update step

    # Delete step
end

include("packages.jl")

end # Module WSL