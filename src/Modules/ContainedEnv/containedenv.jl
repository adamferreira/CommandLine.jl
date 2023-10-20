module ContainedEnv
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

Base.hash(p::Package) = Base.hash(Base.hash(p.name), Base.hash(p.tag))
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

    function App(
        s::CLI.Shell;
        name,
        user,
        from,
        workspace = Base.pwd(),
        docker_run = "bash _l"
    )
        !isnothing(s["CL_DOCKER"]) || @error("Cannot find docker installation")

        # Create temporary workspace for this app (posix path form)
        tmpdir = "containedenv_$(Base.hash(Base.hash(name), Base.hash(from)))"
        workspace = CLI.cygpath(s, Base.joinpath(workspace, tmpdir), "-u")
    
        app = new(name, user, from, docker_run, s, nothing, ["FROM $from"], [], workspace, [], [], [])
        # If the app points to an already running container, we can already open a shell into it
        # TODO: have an 'open' method?
        if container_running(app)
            try
                app.contshell = new_container_shell(app)
            catch
                app.contshell = nothing
            end
        end
        # Setup workspace directory
        @assert !CLI.isdir(app.hostshell, app.workspace)
        CLI.mkdir(app.hostshell, app.workspace)
        @assert CLI.isdir(app.hostshell, app.workspace)

        return app
    end
end

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
home(app::App) = "/home/$(app.user)"

# ---------------------------
# Container related
# ---------------------------
function container_shell_cmd(app::App, usershell::Bool = true)::String
    if usershell
        cmd = Docker.exec_str(app.hostshell;
            argument = "$(container_name(app)) $(app.docker_run)",
            user = app.user,
            tty = true,
            interactive = true
        )
    else
        cmd = Docker.exec_str(app.hostshell;
            argument = "$(container_name(app)) $(app.docker_run)",
            user = app.user,
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
    containers = Docker.containers(app.hostshell, "name=$(container_name(app))")
    # Container already removed, or never created
    if length(containers) == 0
        return nothing
    end
    container = containers[1]
    # Stop the container
    if container["State"] == "running"
        Docker.stop(app.hostshell, container_name(app))
    end

    # Check that the container still exists, but is not running
    container = Docker.containers(app.hostshell, "name=$(container_name(app))")[1]
    container["State"] == "exited" || @error("Could not stop container $(container_name(app))")
    # Destroy the container
    Docker.rm(app.hostshell; force=true, argument=container_name(app))
end


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

# ----- Step 1: local setup ---
function setup_host(app::App)
    pkgs_done = Set{Package}()

    # Run packages's host step callback
    map(p -> begin
        if !(p in pkgs_done)
            if !isnothing(p.install_host)
                p.install_host(app)
            end
            push!(pkgs_done, p)
        end
        end, app.packages
    )
end

# ----- Step 2: image setup ---
function setup_image(app::App, regenerate_image::Bool)
    pkgs_done = Set{Package}()

    # Delete container before destroying related image
    destroy_container(app)

    # Delete previous image if it exists
    if regenerate_image
        destroy_image(app)
    elseif image_exist(app)
        # Stop, proceed to container building
        return nothing
    end

    # Run base packages installation in one line to save layer count
    # Only install package once!
    map(p -> begin
        push!(pkgs_done, p)
        end, filter(p -> p.tag == "base", app.packages)
    )
    COMMENT(app, "Installing base packages")
    RUN(app, "$(pkg_mgr(app)) install -y " * Base.join(map(p -> p.name, collect(pkgs_done)), ' '))

    # Run packages's image step callback
    map(p -> begin
        if !(p in pkgs_done)
            if !isnothing(p.install_image)
                COMMENT(app, "--------------- Installing package $(p.name)#$(p.tag)")
                p.install_image(app)
                COMMENT(app, "---------------")
            end
            push!(pkgs_done, p)
        end
        end, app.packages
    )

    # Now work on the App's temporary workspace
    CLI.indir(app.hostshell, app.workspace) do shell
        # Write Dockerfile #TODO do not put -w
        host_workspace = CLI.cygpath(app.hostshell, app.workspace, "-w")
        open(Base.joinpath(host_workspace, "Dockerfile"), "w+") do file
            for line in app.dockerfile_record
                write(file, line * "\n")
            end
            write(file, "# Switch to custom user" * '\n')
            write(file, "USER $(app.user)" * '\n')
        end

        # Build image
        Docker.image(app.hostshell,
            "build";
            tag = image_name(app),
            argument =  "." # Local Dockerfile in the temporary workspace
        )
    end
end

# ----- Step 3: container setup ---
function setup_container(app::App, user_run_args::String = "")
    # Delete previous container if it exists
    destroy_container(app)

    # Start container 
    container_command = "$(image_name(app)) $(app.docker_run)"
    Docker.run(
        app.hostshell,
        # Mounts
        Base.join(map(m -> Docker.mountstr(app.hostshell, m), app.mounts), ' '),
        # Ports
        Base.join(map(p -> Docker.portstr(app.hostshell, p), app.ports), ' '),
        # Networks
        Base.join(map(n -> Docker.networkstr(app.hostshell, n), app.networks), ' '),
        # User arguments
        user_run_args;
        # Container name and bash process to launch in the container
        argument = container_command,
        # Name of the container to be launched
        name = container_name(app),
        hostname = app.appname,
        user = app.user,
        tty = true,
        detach = true
    )

    # Now that the container is running, we can create a Shell session in it
    app.contshell = new_container_shell(app)

    pkgs_done = Set{Package}()

    # Run packages's container step callback
    map(p -> begin
        if !(p in pkgs_done)
            if !isnothing(p.install_container)
                p.install_container(app)
            end
            push!(pkgs_done, p)
        end
        end, app.packages
    )

    println("Container for app $(app.appname) is ready, you can enter the container with command $(container_shell_cmd(app, true))")
end

"""
- `regenerate_image::Bool`: Skip image construction and use existing image for `app`
"""
function deploy!(app::App; regenerate_image::Bool = true, docker_run_args::String = "")
    try
        #init!(app)
        setup_host(app)
        setup_image(app, regenerate_image)
        setup_container(app, docker_run_args)
    catch e
        # If anything goes wrong, remove everything related to the app
        clean_workspace(app)
        destroy_container(app)
        destroy_image(app)
        rethrow(e)
    finally
        # Destroy temporary workspace now that everything is setup
        clean_workspace(app)
    end
end


export  Package, BasePackage,
        App, ENV, COPY, RUN, 
        add_pkg!, add_mount!, add_port!, deploy!, 
        home,
        container_shell_cmd, new_container_shell, container_running

include("custom_packages.jl")
export  JuliaLinux, GitHubRepo, CommandLineDev


# App for dev container with pretty user_profile and Linux-based sudo user on the container
function DevApp(
    s::CLI.Shell;
    name,
    user,
    from,
    workspace = Base.pwd()
)::App
    # (bash -l -> --login so that bash loads .bash_profile)
    app = App(s, name=name, user=user, from=from, workspace=workspace, docker_run="bash -l")
    # Setup user as root user in the Linux container, and creates its home
    # Also setup user profile file
    COMMENT(app, "Setting up global env vars")
    ENV(app, "USER", app.user)
    ENV(app, "HOME", raw"/home/${USER}")
    COMMENT(app, "Updating package manager")
    RUN(app, "$(pkg_mgr(app)) update -y", "$(pkg_mgr(app)) upgrade -y")
    RUN(app, "$(pkg_mgr(app)) install -y sudo")
    COMMENT(app, "Setting up $(app.user) as a sudo user and create its home")
    RUN(
        app,
        "useradd -r -m -U -G sudo -d $(home(app)) -s /bin/bash -c \"Docker SGE user\" $(app.user)",
        "echo \"$(app.user) ALL=(ALL:ALL) NOPASSWD: ALL\" | sudo tee /etc/sudoers.d/$(app.user)",
        "chown -R $(app.user) $(home(app))",
        "mkdir $(home(app))/projects",
        "chown -R $(app.user) $(home(app))/*"
    )
    # Copy bash_profile (store in CommandLine module) to the container
    #TODO: this seems to not work when CommandLine is installed as a package
    COPY(app, Base.joinpath(@__DIR__, "bash_profile"), "$(home(app))/.bash_profile")
    return app
end

export DevApp
end
