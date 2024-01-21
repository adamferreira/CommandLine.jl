module ContainedEnv
using CommandLine.Paths
import CommandLine as CLI
import CommandLine.Docker as Docker

"""
Package/Project are Installable, they have identifiers:
- `name::String`
- `tag::String`
Package/Project are installed in 3 steps:
- Local (host machine)
- Image ((docker) image)
- Container
Step are invoked for Package as callbacks that take `App` as argument
"""
struct Package
    name::String
    tag::String
    install_host::Union{Nothing,Function}
    install_image::Union{Nothing,Function}
    install_container::Union{Nothing,Function}
    dependencies

    function Package(
        name::String,
        tag::String;
        requires = [],
        install_host::Union{Nothing,Function} = nothing,
        install_image::Union{Nothing,Function} =  nothing,
        install_container::Union{Nothing,Function} = nothing
    )
        return new(name, tag, install_host, install_image, install_container, requires)
    end    
end

BasePackage(pname::String) = Package(pname, "base")
# Overloads for Set{Package}
Base.hash(p::Package) = Base.hash(Base.hash(p.name), Base.hash(p.tag))
Base.isequal(a::Package, b::Package) = Base.isequal(Base.hash(a), Base.hash(b))
function parse_pkg(p::String)
    m = match(r"(?<name>[\w]+)#(?<tag>[\w]*)", p)
    return Package(m["name"], m["tag"])
end


"""
    App
- `appname::String`: Name of the app to be deployed
- `user::String`: Username to use in the container
- `baseimg::String`: Base image name form wich creating ContainedEnv image
- `shell::Shell`: Shell on which docker commands will be launched
"""
mutable struct App
    # Name of the app to be deployed
    appname::String
    # Username to use in the container
    user::String
    # Base image name form wich creating ContainedEnv image
    baseimg::String
    # Home directory for this app
    home::AbstractPath
    # Command to be launched on the container as part of `Docker run` command
    docker_run::String
    # Shell on host (Shell on which docker commands will be launched)
    hostshell::CLI.Shell
    # Shell on container
    contshell::Union{Nothing, CLI.Shell}
    # Docker file content as a tape record
    dockerfile_record::Vector{String}
    # Package dependencies
    packages::Vector{Package}
    # Workspace where all files (including Dockefile) will be copied before copying to image
    workspace::String
    # List of mounts to be passed down to `Docker run`
    mounts::Vector{Docker.Mount}
    # List of port bindings to be passed down to `Docker run`
    ports::Vector{Docker.Port}
    # List of network the app's container is connected to
    networks::Vector{Docker.Network}
    # List of active containers for this `App`
    #containers::Vector{Container}
    function App(
        s::CLI.Shell;
        name,
        user = "root",
        from = "ubuntu:22.04",
        workspace = Base.pwd(),
        docker_run = "bash -l"
    )
        !isnothing(s["CL_DOCKER"]) || @error("Cannot find docker installation")

        # Create temporary workspace for this app (posix path form)
        tmpdir = "containedenv_$(Base.hash(Base.hash(name), Base.hash(from)))"
        workspace = CLI.cygpath(s, Base.joinpath(workspace, tmpdir), "-u")

        # Guess pathtype from image name
        # TODO: Get pathtype from Shell `s` ?
        ptype = occursin("Windows", from) ? WindowsPath : PosixPath
        # Set home depending on the OS
        #TODO: support MacOS
        home =  ptype == PosixPath ? PosixPath("/home/$(user)") : WindowsPath("C:", "Users", user)
    
        app = new(name, user, from, home, docker_run, s, nothing, ["FROM $from"], [], workspace, [], [], [])
        # If the app points to an already running container, we can already open a shell into it
        # TODO: have an 'open' method?
        if container_running(app)
            try
                app.contshell = new_container_shell(app)
            catch
                app.contshell = nothing
            end
        end

        return app
    end
end

"""
    Container
- `app::App`: App that owns this container
- `name::String`: Name of this container
- `shell::Shell`: Shell running inside this container
- `cmd::String`: Docker command used to start this container
"""
mutable struct Container
    app::App
    name::String
    shell::Union{Nothing, CLI.Shell}
    cmd::Union{Nothing, String}
end
app(c::Container)::App = c.app
name(c::Container)::String = c.name
shell(c::Container)::CLI.shell = c.shell
cmd(c::Container)::String = c.cmd

function pkg_mgr(app::App)
    prefix = "DEBIAN_FRONTEND=noninteractive"

    if occursin("debian", app.baseimg)
        return "$prefix dpkg"
    end

    if occursin("ubuntu", app.baseimg)
        return "$prefix apt-get"
    end

    if occursin("fedora", app.baseimg)
        return "$prefix yum"
    end

    if occursin("alpine", app.baseimg)
        return "$prefix apk"
    end
end

function add_pkg!(app::App, p::Package)
    push!(app.packages, p)
    # Also app p's dependencies
    map(_p -> push!(app.packages, _p), p.dependencies)
end

function add_mount!(app::App, m::Docker.Mount)
    push!(app.mounts, m)
end

function add_port!(app::App, p::Docker.Port)
    push!(app.ports, p)
end

function add_network!(app::App, n::Docker.Network)
    push!(app.networks, n)
end

# ---------------------------
# Docker Wrapper
# ---------------------------
container_name(app::App) = "$(app.appname)_ctn"
image_name(app::App) = "$(app.appname)_img"

# ---------------------------
# Utilitaries
# ---------------------------
pathtype(app::App)::Type{AbstractPath} = type(app.home)
home(app::App)::AbstractPath = app.home
user(app::App)::String = app.user
projects(app::App)::AbstractPath = Paths.joinpath(home(app), "projects")

# ---------------------------
# Container related
# ---------------------------
function container_shell_cmd(app::App, usershell::Bool = true)::String
    if usershell
        cmd = Docker.exec(
            argument = "$(container_name(app)) $(app.docker_run)",
            user = user(app),
            tty = true,
            interactive = true
        )
    else
        cmd = Docker.exec(
            argument = "$(container_name(app)) $(app.docker_run)",
            user = user(app),
            tty = false,
            interactive = true
        )
    end
    return cmd
end

function container_running(app::App)::Bool
    return Docker.container_running(app.hostshell, container_name(app))
end

function new_container_shell(app::App)::CLI.Shell
    container_running(app) || @error("Cannot open a new Shell in container $(container_name(app)): container not running")
    #TODO: No not lock with `CLI.Local` (we need cmd /C `$(container_shell_cmd(app, false))`) on Windows
    # Otherwise the command will not work: use CLI.connection_type(app.hostshell)
    return CLI.Shell{CLI.Bash, CLI.Local}(container_shell_cmd(app, false); pwd = "~")
end

function destroy_container(app::App)
    container = Docker.get_container(app.hostshell, container_name(app))
    # Container already removed, or never created
    if isnothing(container)
        return nothing
    end

    # Stop the container if it is running
    if container["State"] == "running"
        Docker.stop(app.hostshell, container_name(app))
    end

    # Check that the container still exists, but is not running
    container = Docker.get_container(app.hostshell, container_name(app))
    if !isnothing(container)
        container["State"] == "exited" || @error("Could not stop container $(container_name(app))")
    end

    # Destroy the container
    Docker.rm(app.hostshell; force=true, argument=container_name(app))
end

#function next_container_name(app::App)
#    return "$(app.appname)_ctn_$(length(app.containers))"
#end
#function container_running(cont::Container)::Bool
#    return Docker.container_running(app.hostshell, container_name(app, cont))
#end
#function create_container(app::App)::Container
#end
#function start_new_container!(app::App)
#end


# ---------------------------
# Image related
# ---------------------------

function image_exist(app::App)
    image = Docker.get_image(app.hostshell, image_name(app))
    return !isnothing(image)
end

function destroy_image(app::App)
    image = Docker.get_image(app.hostshell, image_name(app))
    if isnothing(image)
        return nothing
    end
    Docker.image(app.hostshell, "rm"; argument = image["ID"], force=true)
end

function ENV(app::App, var, val)
    push!(app.dockerfile_record, "ENV $var $val")
end

function LABEL(app::App, var, val)
    push!(app.dockerfile_record, "LABEL $var=$val")
end

function ARG(app::App, var, val)
    push!(app.dockerfile_record, "ARG $var=$val")
end

function COPY(app::App, from, to)
    # Format to posix because app.hostshell must be posix shell for now
    from = CLI.cygpath(app.hostshell, from, "-u")
    file = CLI.basename(app.hostshell, from)
    # Only support copying files to containers
    @assert CLI.isfile(app.hostshell, from)
    # Copy files from host to App's temporary workspace
    CLI.cp(app.hostshell, from, app.workspace)
    push!(app.dockerfile_record, "COPY $file $to")
end

function RUN(app::App, cmds::String...)
    # Pack each commands into one RUN command to avoir having to much layers
    run_cmd = Base.join(vcat(cmds...), " ;\\ \n\t")
    push!(app.dockerfile_record, "RUN $run_cmd")
end

function COMMENT(app::App, line::String)
    push!(app.dockerfile_record, "# $line")
end

function COMMENT(d::App, lines::String...)
    map(l -> COMMENT(d, l), lines...)
end

# ---------------------------
# Host related
# ---------------------------
function clean_workspace(app::App)
    if CLI.isdir(app.hostshell, app.workspace)
        CLI.rm(app.hostshell, "-rf", app.workspace)
    end
end

function create_workspace(app::App)
    @assert !CLI.isdir(app.hostshell, app.workspace)
    CLI.mkdir(app.hostshell, app.workspace)
    @assert CLI.isdir(app.hostshell, app.workspace)
end

# ----- Step 0: local setup (dummy recursive depth-first search) ---
function packages_queue(app::App)
    pkg_queue = Vector{Package}()
    pkgs_done = Set{Package}()
    # First, the base packages
    base_pkg = Set{Package}()
    function inspect_package(p::Package)
        for pp in p.dependencies
            inspect_package(pp)
        end
        # Only install packages once!
        if !(p in pkgs_done)
            p.tag == "base" ? push!(base_pkg, p) : push!(pkg_queue, p)
            push!(pkgs_done, p)
        end
    end

    # width search
    for p in app.packages
        inspect_package(p)
    end

    return base_pkg, pkg_queue
end

# ----- Step 1: local setup ---
function setup_host(app::App)
    base_pkg, pkg_queue = packages_queue(app)
    # Run packages's host step callback
    map(p -> begin
        if !isnothing(p.install_host)
            p.install_host(app)
        end
    end, pkg_queue)
end

# ----- Step 2: image setup ---
function setup_image(app::App, regenerate_image::Bool)
    base_pkg, pkg_queue = packages_queue(app)

    # Delete container before destroying related image
    destroy_container(app)

    # Delete previous image if it exists
    if image_exist(app)
        if regenerate_image
            destroy_image(app)
        end
    end

    # Run base packages installation in one line to save layer count
    if length(base_pkg) > 0 # Do not update repo cache if their is no package to install, because it is quite space heavy
        COMMENT(app, "Installing base packages")
        RUN(app, "$(pkg_mgr(app)) update -y")
        RUN(app, "$(pkg_mgr(app)) upgrade -y")
        RUN(app, "$(pkg_mgr(app)) install -y " * Base.join(map(p -> p.name, collect(base_pkg)), ' '))
    end

    # Run packages's image step callback
    map(p -> begin
        if !isnothing(p.install_image)
            COMMENT(app, "--------------- Installing package $(p.name)#$(p.tag)")
            p.install_image(app)
            COMMENT(app, "---------------")
        end
    end, pkg_queue)

    # Now work on the App's temporary workspace
    CLI.indir(app.hostshell, app.workspace) do shell    
        # Write Dockerfile #TODO do not put -w
        host_workspace = CLI.cygpath(shell, app.workspace, "-w")
        open(Base.joinpath(host_workspace, "Dockerfile"), "w+") do file
            for line in app.dockerfile_record
                write(file, line * "\n")
            end
            # Switch to custom user if non-root
            if user != "root"
                write(file, "# Switch to custom user" * '\n')
                write(file, "USER $(user(app))" * '\n')
            end
        end

        # Build image
        # Docker < 23.0 : docker image build --tag monimage .
        # Docker > 23.0 : docker buildx build --tag monimage .
        DOCKERVER = 22.0
        if DOCKERVER > 23.0
            Docker.buildx(shell,
                "build";
                tag = image_name(app),
                argument =  "." # Local Dockerfile in the temporary workspace
            )
        else
            Docker.image(shell,
                "build";
                tag = image_name(app),
                argument =  "." # Local Dockerfile in the temporary workspace
            )
        end
    end
end

# ----- Step 3: container setup ---
function setup_container(app::App, user_run_args::String)
    base_pkg, pkg_queue = packages_queue(app)
    # Delete previous container if it exists
    destroy_container(app)

    # Start container 
    container_command = "$(image_name(app)) $(app.docker_run)"
    Docker.run(app.hostshell,
        # Mounts
        Base.join(map(m -> Base.string(m), app.mounts), ' '),
        # Ports
        Base.join(map(p -> Base.string(p), app.ports), ' '),
        # Networks
        Base.join(map(n -> Base.string(n), app.networks), ' '),
        # User arguments
        user_run_args;
        # Container name and bash process to launch in the container
        argument = container_command,
        # Name of the container to be launched
        name = container_name(app),
        hostname = app.appname,
        user = user(app),
        tty = true,
        detach = true
    )

    # Now that the container is running, we can create a Shell session in it
    app.contshell = new_container_shell(app)

    # Run packages's container step callback
    map(p -> begin
        if !isnothing(p.install_container)
            p.install_container(app)
        end
    end, pkg_queue)
    println("Container for app $(app.appname) is ready, you can enter the container with command `$(container_shell_cmd(app, true))`")
end

function clean_all!(app::App)
    clean_workspace(app)
    destroy_container(app)
    destroy_image(app)
end

"""
- `regenerate_image::Bool`: Skip image construction and use existing image for `app`
"""
function deploy!(
    app::App;
    regenerate_image::Bool = false,
    docker_run_args::String = ""
)
    try
        create_workspace(app)
        setup_host(app)
        setup_image(app, regenerate_image)
        setup_container(app, docker_run_args)
    catch e
        # If anything goes wrong, remove everything related to the app
        clean_all!(app)
        rethrow(e)
    finally
        # Destroy temporary workspace now that everything is setup
        clean_workspace(app)
    end
    
end


export  Package, BasePackage,
        App, Container, ENV, COPY, RUN,
        add_pkg!, add_mount!, add_port!, deploy!, clean_all!,
        home,
        container_shell_cmd, new_container_shell, container_running, packages_queue

include("custom_packages.jl")
export  JuliaLinux


# App for dev container with pretty user_profile and Linux-based sudo user on the container
function DevApp(
    s::CLI.Shell;
    name,
    user = "root",
    from = "ubuntu:22.04",
    workspace = Base.pwd()
)::App
    # (bash -l -> --login so that bash loads .bash_profile)
    app = App(s, name=name, user=user, from=from, workspace=workspace, docker_run="bash -l")
    # Setup custom user as a sudo-user and creates its home directory
    user_env = Package(
        "user_env", from;
        install_image = app -> begin
            COMMENT(app, "Setting up global env vars")
            ENV(app, "USER", ContainedEnv.user(app))
            ENV(app, "HOME", raw"/home/${USER}")
            #RUN(app, "$(pkg_mgr(app)) update -y", "$(pkg_mgr(app)) upgrade -y")
            #RUN(app, "$(pkg_mgr(app)) install -y sudo")
            COMMENT(app, "Setting up $(ContainedEnv.user(app)) as a sudo user and create its home")
            RUN(
                app,
                "useradd -r -m -U -G sudo -d $(home(app)) -s /bin/bash -c \"Docker SGE user\" $(ContainedEnv.user(app))",
                "echo \"$(ContainedEnv.user(app)) ALL=(ALL:ALL) NOPASSWD: ALL\" | sudo tee /etc/sudoers.d/$(ContainedEnv.user(app))",
                "chown -R $(ContainedEnv.user(app)) $(home(app))",
                "mkdir $(projects(app))",
                "chown -R $(ContainedEnv.user(app)) $(home(app))/*"
            )
        end,
        requires = [BasePackage("sudo")]
    )

    # Copy bash_profile (store in CommandLine module) to the container
    # Also format it to unix format
    bash_profile = Package(
        "bash_profile", from;
        install_image = app -> begin
            img_profile = Paths.joinpath(home(app), ".bash_profile")
            COPY(app, Base.joinpath(@__DIR__, "bash_profile"), img_profile)
            RUN(app, "dos2unix $(img_profile)")
        end,
        requires = [BasePackage("dos2unix")]
    )
    # Do not setup user 'root', it exists by default
    # And do not bother with creating a pretty bash profile
    if user != "root"
        add_pkg!(app, user_env)
    end
    add_pkg!(app, bash_profile)
    return app
end

export DevApp
end
