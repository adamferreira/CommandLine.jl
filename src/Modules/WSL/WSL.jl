module WSL

import CommandLine.Paths as Paths
import CommandLine as CLI
using Crayons

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
export PathBridge

joinbridge(pb::PathBridge, args...) = PathBridge(Paths.joinpath(pb.host, args...) => Paths.joinpath(pb.instance, args...))
export joinbridge

global WSLJLHOSTHOME = Paths.joinpath(Paths.pathtype()(ENV["HOME"]), ".wsljl")
export WSLJLHOSTHOME
struct Tarball
    name::String
    url::Union{Nothing, String}
    hostpath::Union{Nothing, Paths.AbstractPath, String}
end
export Tarball

function LocalTarball(path::Union{Paths.AbstractPath, String})::Tarball
    ppath = Paths.pathtype()(path)
    return Tarball(basename(string(ppath)), nothing, ppath)
end
export LocalTarball

function RemoteTarball(url::String)::Tarball
    name = split(url, '/')[end]
    return Tarball(name, url, nothing)
end
export RemoteTarball

RemoteUbuntu24() = RemoteTarball("https://cloud-images.ubuntu.com/wsl/releases/24.04/current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz")

function SETUP_WSLJL()
    if !isdir(WSLJLHOSTHOME |> string)
        mkdir(WSLJLHOSTHOME |> string)
    end
    if !isfile(Paths.joinpath(WSLJLHOSTHOME, "WSLJL_Default_Base.tar.gz") |> string)
        tarball = RemoteUbuntu24()
        location = string(Paths.joinpath(WSLJLHOSTHOME, "WSLJL_Default_Base.tar.gz"))
        @info "Downloading `$(tarball.name)`"
        run(`curl $(tarball.url) --output $(location)`)
    end
end
mutable struct WSLInstance
    # Custom name of the instance
    name::String
    # (sudo) user on the instance
    user::String
    # Shell running on the host machine/OS
    hostshell::Union{Nothing, CLI.Shell}
    # Workspace where all files will be copied before copying into the running instance, lives on host
    workspace::Paths.WindowsPath
    # Package manager
    pkmg
    # Where to find the tarball to deploy this instance
    tarball::Tarball

    function WSLInstance(
        name::String,
        user::String,
        tarball::Tarball = Tarball("Default", nothing, Paths.joinpath(WSLJLHOSTHOME, "WSLJL_Default_Base.tar.gz")),
        s::CLI.Shell = CLI.GitBash();
    )
        # Create temporary workspace for this app (posix path form)
        wpname = "$(name)_$(Base.hash(name))"
        workspace_host = Paths.pathtype()(Base.joinpath(Base.pwd(), wpname))

        wsli = new(name, user, s, workspace_host, nothing, tarball)
        wsli.pkmg = PkgManager(wsli)
        clean_workspace(wsli)

        if !isdir(fsroot(wsli) |> string)
            mkdir(fsroot(wsli) |> string)
        end

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
# Filesystem directory for the instance
# Contains the .vhdx file and other utils used by this package
fsroot(wsli::WSLInstance) = Paths.joinpath(WSLJLHOSTHOME, "Instance_$(name(wsli))")
export fsroot
sudo(wsli::WSLInstance) = user(wsli) ==  "root" ? "" : "sudo"

pkmg(wsli::WSLInstance) = wsli.pkmg

function host_tarball_location(wsli::WSLInstance)
    return wsli.tarball.hostpath
end

function host_tarball_exists(wsli::WSLInstance)
    return isfile(string(host_tarball_location(wsli)))
end

# Drive that is shared between WSL instances
wsl_shared_drive() = Paths.PosixPath("/mnt", "wsl")

# Tells whether a given paths exists on the instance
function path_exists_on_instance(wsli::WSLInstance, path::Union{String, Paths.AbstractPath})
    # Trick to see if a package is already on the instance
    # Simply try to fetch its datafile
    try
        # Will throw if datafile does not exist
        run_on_instance(wsli, "sudo ls -lah $(path)")
        return true
    catch e
        return false
    end
end

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

function __run_on_instance(wsli::WSLInstance, cmd, flush::Bool = false; user = "root", dir = "/home")
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

    if flush
        # Will only update the last line in the console
        # This will avoid long output put will still showcase a progress
        CLI.run_with(hostshell(wsli), join(c, " "), x -> print("$(x)\u001b[1000D"))
        println(" \u001b[1000D")
    else
        CLI.run_with(hostshell(wsli), join(c, " "), x -> nothing)
    end
end

run_on_instance(wsli::WSLInstance, cmd, flush::Bool = false) = __run_on_instance(wsli, cmd; user = user(wsli), dir = home(wsli))
run_on_instance_as_root(wsli::WSLInstance, cmd, flush::Bool = false) = __run_on_instance(wsli, cmd; user = "root", dir = "/home")
export run_on_instance, run_on_instance_as_root

function copy_to_instance(wsli::WSLInstance, pb::PathBridge)
    instance_dir = CLI.parent(hostshell(wsli), pb.instance)
    # Create parent dir if it doesn't exists yet
    try
        run_on_instance(wsli, "mkdir -p $(instance_dir)")
    catch e
        # Do Nothing
    finally
        run_on_instance(wsli, "sudo cp -r $(mounted_path(pb.host)) $(pb.instance)")
        run_on_instance(wsli, "sudo chown -R $(user(wsli)) $(pb.instance)")
    end
end
copy_to_host(wsli::WSLInstance, pb::PathBridge) = run_on_instance(wsli, "cp -r $(pb.instance) $(mounted_path(pb.host))")


function log(wsli::WSLInstance, loglevel::Symbol, msg...) 
    c = :blue
    if loglevel == :info
        c = :blue
    end

    if loglevel == :warn
        c = (255, 128, 0)
    end

    if loglevel == :error
        c = :red
    end

    println(Crayon(foreground = c), "[$(name(wsli))]: ", Crayon(foreground = :white), msg...)
end

info(wsli::WSLInstance, msg...) = log(wsli, :info, msg...)
warn(wsli::WSLInstance, msg...) = log(wsli, :warn, msg...)
error(wsli::WSLInstance, msg...) = log(wsli, :error, msg...)

function clean_workspace(wsli::WSLInstance)
    if isdir(workspace(wsli) |> string)
        warn(wsli, "Cleaning workspace `$(workspace(wsli))`")
        rm(workspace(wsli) |> string, recursive = true)
    end
end
export clean_workspace

function create_workspace(wsli::WSLInstance)
    if isdir(hostshell(wsli) |> string)
        clean_workspace(wsli)
    end
    info(wsli, "Creating workspace `$(workspace(wsli))`")
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

exists(wsli::WSLInstance)::Bool = name(wsli) in list_instances(hostshell(wsli))
export exists
isrunning(wsli::WSLInstance)::Bool = name(wsli) in running_instances(hostshell(wsli))
export isrunning

# TODO: Import already setup wsljl tarballs 
# import

unregister!(wsli::WSLInstance) = run_on_host_interactive(wsli, `wsl --unregister $(name(wsli))`)

function deploy!(
    wsli::WSLInstance;
    regenerate_if_exists::Bool = false,
)

    function deploy_from_local_tarball(wsli::WSLInstance, tarball::Paths.AbstractPath)
        # Check tarball
        if !isfile(tarball |> string)
            throw("Could not find tarball $(tarball)")
        end

        # Setup filesystem root
        if !isdir(fsroot(wsli) |> string)
            try
                mkdir(fsroot(wsli) |> string)
            catch e
                error(wsli, "Could not create filesystem root $(fsroot(wsli))")
                throw(e)
            end
        end

        # Create instance
        info(wsli, "Deploying instance `$(name(wsli))`")
        #"from $(tarball) with fs root $(fsroot(wsli))")
        if exists(wsli)
            throw("Instance $(name(wsli)) already exists")
        end
        run_on_host_interactive(wsli, `wsl --import $(name(wsli)) $(fsroot(wsli)) $(tarball)`)

        # Now that the instance is running, setup the user
        # 'sudo' group in Fedora is 'wheel'
        info(wsli, "Creating user `$(user(wsli))`")
        p = joinpath(@__DIR__, "wsl_instance_setup.sh")
        run_on_instance_as_root(wsli, "bash $(mounted_path(p)) $(user(wsli))")
        # At this point, custom user exists
        run_on_instance(wsli, "sudo mkdir $(cachedir(wsli))")
        run_on_instance(wsli, "sudo chown -R $(user(wsli)) $(cachedir(wsli))")
        # Create user bashrc
        bash_profile = Paths.pathtype()(joinpath(dirname(@__DIR__), "ContainedEnv", "bash_profile"))
        copy_to_instance(wsli, PathBridge(bash_profile => Paths.joinpath(home(wsli), ".bash_profile")))
        bashrc = PathBridge(Paths.joinpath(workspace(wsli), "bashrc") => Paths.joinpath(home(wsli), ".bashrc"))
        copy_to_host(wsli, bashrc)
        open(bashrc.host |> string, "a") do f
            write(f, "\n")
            write(f, "export WSLJLHOME=$(cachedir(wsli))" * "\n")
            # Used to load individual package's bashrc
            load_loop = """
                for dir in \${WSLJLHOME}/packages/*/; do
                    if [ -d \${dir} ]; then
                        if [ -f \${dir}/bashrc.sh ]; then
                            source \${dir}/bashrc.sh
                        fi
                    fi
                done
            """
            write(f, load_loop * "\n\n")
            # Also load user profile
            load_profile = """
                if [ -f ~/.bash_profile ]; then
                    . ~/.bash_profile
                fi
            """
            write(f, load_profile * "\n\n")

            # Change /etc/wsl.conf to make user(wsli) the default logged user !
            wslconf = PathBridge(Paths.joinpath(workspace(wsli), "wsl.conf") => Paths.PosixPath("/etc", "wsl.conf"))
            open(wslconf.host |> string, "w+") do f
                write(f, "[boot]\n")
                write(f, "systemd=true\n")
                write(f, "[user]\n")
                write(f, "default=$(user(wsli))\n")
                write(f, "[interop]\n")
                write(f, "enabled=true\n")
                write(f, "appendWindowsPath=false\n")
            end
            copy_to_instance(wsli, wslconf)
            # Stop the instance to force restart and apply changes
            # Will restart automatically next time `run_on_host*` is called. 
            stop(wsli)
        end
        copy_to_instance(wsli, bashrc)
    end

    function deploy_from_remote_tarball(wsli::WSLInstance)
        info(wsli, "Downloading `$(wsli.tarball.name)`")
        run_on_host_interactive(wsli, `curl $(wsli.tarball.url) --output $(host_tarball_location(wsli))`)
        deploy_from_local_tarball(wsli, host_tarball_location(wsli))
    end

    try
        create_workspace(wsli)
        if exists(wsli)
            if regenerate_if_exists
                warn(wsli, "Wipping instance `$(name(wsli))`")
                unregister!(wsli)
            else
                warn(wsli, "Instance `$(name(wsli))` already exists")
            end
        end

        if !exists(wsli) || (exists(wsli) && regenerate_if_exists)
            if host_tarball_exists(wsli)
                deploy_from_local_tarball(wsli, host_tarball_location(wsli))
            else
                deploy_from_remote_tarball(wsli)
            end
        end
        instantiate!(wsli.pkmg)
    catch e
        # If anything goes wrong, remove everything related to the app
        if exists(wsli)
            #unregister!(wsli)
        end
        rethrow(e)
    finally
        # Destroy temporary workspace now that everything is setup
        clean_workspace(wsli)
    end
end
export deploy!

# Open session in the instance
function enter(wsli::WSLInstance)
    # Suppress Errors
    try
        run_on_host_interactive(wsli, `wsl --distribution $(name(wsli)) --user $(user(wsli)) --cd $(home(wsli))`)
    catch e
    end
end
export enter

function stop(wsli::WSLInstance)
    run_on_host_interactive(wsli, `wsl --terminate $(name(wsli))`)
end
export stop



struct Package
    name::String
    version::Union{Nothing, VersionNumber, String}
    # Callback (WSLInstance) -> Bool to tell whether we should run the package building/compilation process
    should_build::Function
    # Callback (WSLInstance) -> Bool to tell whether we should run the package installation process
    should_install::Function
    # Callback (WSLInstance) -> Bool to tell whether we should run the package update process
    should_update::Function
    # Callback (WSLInstance) -> Bool to tell whether we should run the package deletion process
    should_delete::Function
    # Callback (WSLInstance) -> Nothing to generate bash commands for the package building/compilation process
    on_build::Union{Nothing, Function}
    # Callback (WSLInstance) -> Nothing to generate bash commands for the package installation process
    on_install::Union{Nothing, Function}
    # Callback (WSLInstance) -> Nothing to generate bash commands for the package update process
    on_update::Union{Nothing, Function}
    # Callback (WSLInstance) -> Nothing to generate bash commands for the package deletion process
    on_delete::Union{Nothing, Function}
    # Callback (WSLInstance) -> Nothing to generate bash commands for user setup
    on_bashrc::Union{Nothing, Function}
    # Callback (WSLInstance) -> Vector{Paths.AbstractPath} that gives files or folders exposed by the package, usefull for shared packages
    exposes::Union{Nothing, Function}
    dependencies

    function Package(
        name::String,
        version::Union{Nothing, VersionNumber, String} = nothing;
        requires = [],
        should_build::Union{Nothing, Function} = nothing,
        should_install::Union{Nothing, Function} = nothing,
        should_update::Union{Nothing, Function} = nothing,
        should_delete::Union{Nothing, Function} = nothing,
        on_build::Union{Nothing, Function} = nothing,
        on_install::Union{Nothing, Function} = nothing,
        on_update::Union{Nothing, Function} = nothing,
        on_delete::Union{Nothing, Function} = nothing,
        on_bashrc::Union{Nothing, Function} = nothing,
        exposes::Union{Nothing, Function} = nothing
    )
        # Default callbacks
        __should_build = nothing
        __should_install = nothing
        __should_update = nothing
        __should_delete = nothing
        # For installation, if we already have scripts on the instance, it means the package is already installed there
        # and does not need installation
        if isnothing(should_install)
            __should_install = wsli -> begin
                p = current_pkg(wsli)
                return !path_exists_on_instance(wsli, pkg_install_file(wsli.pkmg, p).instance)
            end
        else
            __should_install = should_install
        end
        
        # Never uptate of delete until told otherwise
        __should_build = isnothing(should_build) ? (wsli -> false) : should_build
        __should_update = isnothing(should_update) ? (wsli -> false) : should_update
        __should_delete = isnothing(should_delete) ? (wsli -> false) : should_delete
        __exposes = isnothing(exposes) ? (wsli -> Vector{Paths.AbstractPath}()) : exposes
        return new(
            name, version, 
            __should_build, __should_install, __should_update, __should_delete, 
            on_build, on_install, on_update, on_delete, on_bashrc, 
            __exposes,
            requires
        )
    end
end
export Package
name(p::Package) = p.name
version(p::Package) = p.version
versionstr(p::Package) = isnothing(version(p)) ? "default" : "$(version(p))"
uid(p::Package)::String = "$(Base.hash(name(p)))__$(Base.hash(versionstr(p)))"
pretty_name(p::Package) = "$(name(p))_" * replace("$(versionstr(p))", "." => "_")

# Overloads for Set{Package} (colision detection)
Base.hash(p::Package) = Base.hash(Base.hash(name(p)), Base.hash(versionstr(p)))
Base.isequal(a::Package, b::Package) = Base.isequal(Base.hash(a), Base.hash(b))

mutable struct PackageData
    already_on_host::Bool
    already_on_instance::Bool
    should_run_build::Bool
    should_run_install::Bool
    should_run_update::Bool
    should_run_delete::Bool

    function PackageData()
        return new(false, false, false, false, false, false)
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
    current_pkg_cmds_buffer::Vector{String}
    current_pkg_env_buffer::Dict{String, String}
    current_pkg_mutex::Base.Threads.Condition

    function PkgManager(wsli::WSLInstance)
        pkmg = new(wsli, Dict{Package, PackageData}(), Set{Package}(), nothing, Vector{String}(), Dict{String, String}(), Base.Threads.Condition())
        return pkmg
    end
end
export PkgManager

# Where all packages data are stored on the instance
storedir(pkmg::PkgManager) = PathBridge(Paths.joinpath(workspace(pkmg.wsli), "packages") => Paths.joinpath(cachedir(pkmg.wsli), "packages"))
# CSV that stores, for each packages, their detailed information
storefile(pkmg::PkgManager) = joinbridge(storedir(pkmg), "packages.csv")
# For a given package, gives the path to its data folder
pkg_datadir(pkmg::PkgManager, p::Package) = joinbridge(storedir(pkmg), pretty_name(p))
pkg_datadir(wsli::WSLInstance, p::Package) = pkg_datadir(pkmg(wsli), p)
export pkg_datadir
# Workspace used by `install` and `build` steps of a package
pkg_build_workspace(pkmg::PkgManager, p::Package) = joinbridge(pkg_datadir(pkmg, p), "build").instance
pkg_build_workspace(wsli::WSLInstance, p::Package) = pkg_build_workspace(pkmg(wsli), p)
export pkg_build_workspace
pkg_install_workspace(pkmg::PkgManager, p::Package) = joinbridge(pkg_datadir(pkmg, p), "install").instance
pkg_install_workspace(wsli::WSLInstance, p::Package) = pkg_install_workspace(pkmg(wsli), p)
export pkg_install_workspace

# Files used to install, update, or delete a package
pkg_bashrc_file(pkmg::PkgManager, p::Package) = joinbridge(pkg_datadir(pkmg, p), "bashrc.sh")
pkg_build_file(pkmg::PkgManager, p::Package) = joinbridge(pkg_datadir(pkmg, p), "build.sh")
pkg_install_file(pkmg::PkgManager, p::Package) = joinbridge(pkg_datadir(pkmg, p), "install.sh")
pkg_update_file(pkmg::PkgManager, p::Package) = joinbridge(pkg_datadir(pkmg, p), "update.sh")
pkg_delete_file(pkmg::PkgManager, p::Package) = joinbridge(pkg_datadir(pkmg, p), "delete.sh")


current_pkg(pkmg::PkgManager) = pkmg.current_pkg
current_pkg(wsli::WSLInstance) = current_pkg(wsli.pkmg)
export current_pkg

function CMD(pkmg::PkgManager, cmd::String)
    push!(pkmg.current_pkg_cmds_buffer, cmd)
end
CMD(wsli::WSLInstance, cmd::String) = CMD(wsli.pkmg, cmd)
export CMD

function SETENV(pkmg::PkgManager, var, val)
    pkmg.current_pkg_env_buffer[string(var)] = string(val) 
end
SETENV(wsli::WSLInstance, var, val) = SETENV(wsli.pkmg, var, val)
export SETENV

function ADDENV(pkmg::PkgManager, var, val)
    SETENV(pkmg, var, "\${$(var)}:$(val)")
end
ADDENV(wsli::WSLInstance, var, val) = ADDENV(wsli.pkmg, var, val)
export ADDENV

function has_pkg(pkmg::PkgManager, p::Package)
    return haskey(pkmg.store, p)
end

function with_package(body::Function, pkmg::PkgManager, p::Package)
    lock(pkmg.current_pkg_mutex) do
        __save = pkmg.current_pkg
        pkmg.current_pkg = p
        pkmg.current_pkg_cmds_buffer = Vector{String}()
        pkmg.current_pkg_env_buffer = Dict{String, String}()
        body(p)
        pkmg.current_pkg = __save
    end
end

function fetch_pkg_data!(pkmg::PkgManager, p::Package)
    if !has_pkg(pkmg, p)
        dt = PackageData()
        with_package(pkmg, p) do package
            # Cache result, callbacks are only run once
            dt.should_run_build = package.should_build(pkmg.wsli)
            dt.should_run_install = package.should_install(pkmg.wsli)
            dt.should_run_update = package.should_update(pkmg.wsli)
            dt.should_run_delete = package.should_delete(pkmg.wsli)
            # Also trigger `exposes` callback
            package.exposes(pkmg.wsli)
        end
        pkmg.store[p] = dt
    end
    return pkmg.store[p]
end

function add_pkg!(pkmg::PkgManager, p::Package)
    push!(pkmg.packages, p)
    for pp in p.dependencies
        add_pkg!(pkmg, pp)
    end
end
function add_pkg!(wsli::WSLInstance, p::Package)
    add_pkg!(wsli.pkmg, p)
end

function setup_pkg!(pkmg::PkgManager, p::Package)
    # Register package to store
    dt = fetch_pkg_data!(pkmg, p)

    # Package already processed, quit
    if dt.already_on_host
        return nothing
    end

    if !dt.already_on_instance
        # Create package cache folder on instance
        run_on_instance(pkmg.wsli, "sudo mkdir -p $(pkg_datadir(pkmg, p).instance)")
        run_on_instance(pkmg.wsli, "sudo mkdir -p $(pkg_build_workspace(pkmg, p))")
        run_on_instance(pkmg.wsli, "sudo mkdir -p $(pkg_install_workspace(pkmg, p))")
        run_on_instance(pkmg.wsli, "sudo chown -R $(user(pkmg.wsli)) $(pkg_datadir(pkmg, p).instance)")
    end

    # Create package cache folder on host
    if !isdir(pkg_datadir(pkmg, p).host |> string)
        mkdir(pkg_datadir(pkmg, p).host |> string)
    end

    dt.already_on_host = true
    dt.already_on_instance = true

    pkmg.store[p] = dt
    return nothing
end

function build_pkg!(pkmg::PkgManager, p::Package)
    # -------------------------------------------------
    # build.sh
    # -------------------------------------------------
    if !pkmg.store[p].should_run_build
        return
    end

    # Generate `build.sh` of package of host, and send it to the instance
    if !isfile(pkg_build_file(pkmg, p).host |> string)
        touch(pkg_build_file(pkmg, p).host |> string)
    end
    if !isnothing(p.on_build)
        # This will fill `pkmg.current_pkg_cmds_buffer`
        with_package(pkmg, p) do package
            package.on_build(pkmg.wsli)
            # Now, put the content in the package's file
            open(pkg_build_file(pkmg, package).host |> string, "w+") do f
                for line in pkmg.current_pkg_cmds_buffer
                    write(f, line * "\n")
                end
            end
        end
    end
    copy_to_instance(pkmg.wsli, pkg_build_file(pkmg, p))

    # Build actual package
    info(pkmg.wsli, "Building package `$(name(p)): $(versionstr(p))`")
    run_on_instance(pkmg.wsli, "sh $(pkg_build_file(pkmg, p).instance)", false)
    pkmg.store[p].should_run_build = false
    return nothing
end

function install_pkg!(pkmg::PkgManager, p::Package)
    # -------------------------------------------------
    # install.sh
    # -------------------------------------------------
    if !pkmg.store[p].should_run_install
        return
    end

    # Generate `install.sh` of package of host, and send it to the instance
    if !isfile(pkg_install_file(pkmg, p).host |> string)
        touch(pkg_install_file(pkmg, p).host |> string)
    end
    if !isnothing(p.on_install)
        # This will fill `pkmg.current_pkg_cmds_buffer`
        with_package(pkmg, p) do package
            package.on_install(pkmg.wsli)
            # Now, put the content in the package's file
            open(pkg_install_file(pkmg, package).host |> string, "w+") do f
                for line in pkmg.current_pkg_cmds_buffer
                    write(f, line * "\n")
                end
            end
        end
    end
    copy_to_instance(pkmg.wsli, pkg_install_file(pkmg, p))

    # Install actual package
    info(pkmg.wsli, "Installing package `$(name(p)): $(versionstr(p))`")
    run_on_instance(pkmg.wsli, "sh $(pkg_install_file(pkmg, p).instance)", true)

    pkmg.store[p].should_run_install = false
    return nothing
end


function bashrc_pkg!(pkmg::PkgManager, p::Package)
    # -------------------------------------------------
    # bashrc.sh
    # -------------------------------------------------
    # Generate `install.sh` of package of host, and send it to the instance
    if !isfile(pkg_bashrc_file(pkmg, p).host |> string)
        touch(pkg_bashrc_file(pkmg, p).host |> string)
    end
    if !isnothing(p.on_bashrc)
        # This will fill `pkmg.current_pkg_cmds_buffer`
        with_package(pkmg, p) do package
            package.on_bashrc(pkmg.wsli)
            # Now, put the content in the package's file
            open(pkg_bashrc_file(pkmg, p).host |> string, "w+") do f
                for line in pkmg.current_pkg_cmds_buffer
                    write(f, line * "\n")
                end
                for (var, val) in pkmg.current_pkg_env_buffer
                    write(f, "export $(var)=$(val)\n")
                end
            end
        end
    end
    copy_to_instance(pkmg.wsli, pkg_bashrc_file(pkmg, p))
    info(pkmg.wsli, "Setup package `$(name(p)): $(versionstr(p))`")
    return nothing
end

function instantiate!(pkmg::PkgManager)
    # Local data setup
    if !isdir(storedir(pkmg).host |> string)
        mkdir(storedir(pkmg).host |> string)
    end

    # Sort by dependencies depth
    function __deph(p::Package)
        if length(p.dependencies) == 0
            return 0
        else
            return 1 + maximum(map(pp -> __deph(pp), p.dependencies))
        end
    end
    sorted_packages = collect(pkmg.packages)
    sorted_packages = sort!(sorted_packages, by = x -> __deph(x))

    for p in sorted_packages
        with_package(pkmg, p) do package
            setup_pkg!(pkmg, package)
            build_pkg!(pkmg, package)
            install_pkg!(pkmg, package)
            bashrc_pkg!(pkmg, package)
        end
    end
end

include("packages.jl")
SETUP_WSLJL()
end # Module WSL