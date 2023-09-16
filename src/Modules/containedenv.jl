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
    cbhost::Union{Nothing,Function}
    cbimgage::Union{Nothing,Function}
    cbcontainer::Union{Nothing,Function}
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
    appname::String
    user::String
    baseimg::String
    shell::CLI.Shell
    # Decoke file content as a tape record
    dockerfile_record::Vector{String}
    # Package dependencies
    packages::Vector{Package}
    # Workspace where all files (including Dockefile) wlll be copied before
    # Copying to image
    workspace::String

    function App(
        s::CLI.Shell;
        name,
        user,
        from,
        workspace = Base.pwd()
    )
        !isnothing(s["CL_DOCKER"]) || @error("Cannot find docker installation")

        # Create temporary workspace for this app (posix path form)
        tmpdir = "containedenv_$(Base.hash(Base.hash(name), Base.hash(from)))"
        workspace = CLI.cygpath(s, Base.joinpath(workspace, tmpdir), "-u")
    
        app = new(name, user, from, s, ["FROM $from"], [], workspace)
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

# ---------------------------
# Docker Wrapper
# ---------------------------
container_name(app::App) = "$(app.appname)_ctn"
image_name(app::App) = "$(app.appname)_img"
home(app::App) = "/home/$(app.user)"

function destroy_container(app::App)
    containers = Docker.containers(app.shell, "name=$(container_name(app))")
    # Container already destroyed
    if length(containers) == 0
        return nothing
    end
    container = containers[1]
    # Stop the container
    if container["State"] == "running"
        Docker.stop(app.shell, container_name(app))
    end

    container = Docker.containers(app.shell, "name=$(container_name(app))")[1]
    container["State"] == "exited" || @error("Could not stop container $(container_name(app))")
    # Destroy the container
    Docker.rm(app.shell; force=true, argument=container_name(app))
end

function destroy_image(app::App)
    image = Docker.get_image(app.shell, image_name(app))
    # Image already destroyed
    if isnothing(image)
        return nothing
    end

    Docker.image(app.shell, "rm"; argument = image["ID"], force=true)
end

# ---------------------------
# Image related
# ---------------------------
function ENV(app::App, var, val)
    push!(app.dockerfile_record, "ENV $var=$val")
end

function COPY(app::App, from, to)
    # Format to posix because app.shell must be posix shell for now
    from = CLI.cygpath(app.shell, from, "-u")
    file = CLI.basename(app.shell, from)
    # Only support copying files to containers
    @assert CLI.isfile(app.shell, from)
    # Copy files from host to App's temporary workspace
    CLI.cp(app.shell, from, app.workspace)
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


# ----- Step 0: init all boilerplate ---
function init!(app::App)
    # The begining of every containedenv is the same
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
    @assert !CLI.isdir(app.shell, app.workspace)
    CLI.mkdir(app.shell, app.workspace)
    @assert CLI.isdir(app.shell, app.workspace)

    # Copy bash_profile (store in CommandLine module) to the container
    COPY(app, Base.joinpath(@__DIR__, "bash_profile"), "$(home(app))/.bash_profile")
end

function clean_workspace(app::App)
    if CLI.isdir(app.shell, app.workspace)
        CLI.rm(app.shell, "-rf", app.workspace)
    end
end

# ----- Step 1: local setup ---
function setup_host(app::App)
    pkgs_done = Set{Package}()

    # Run packages's host step callback
    map(p -> begin
        if !(p in pkgs_done)
            if !isnothing(p.cbhost)
                p.cbhost(app)
            end
            push!(pkgs_done, p)
        end
        end, app.packages
    )
end

# ----- Step 2: image setup ---
function setup_image(app::App, clean_image)
    pkgs_done = Set{Package}()

    # Delete container before destroying related image
    destroy_container(app)

    # Delete previous image if it exists
    if clean_image
        destroy_image(app)
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
            if !isnothing(p.cbimgage)
                COMMENT(app, "Installing package $(p.name)#$(p.tag)")
                p.cbimgage(app)
            end
            push!(pkgs_done, p)
        end
        end, app.packages
    )

    # Now work on the App's temporary workspace
    CLI.indir(app.shell, app.workspace) do shell
        # Write Dockerfile #TODO do not put -w
        host_workspace = CLI.cygpath(app.shell, app.workspace, "-w")
        open(Base.joinpath(host_workspace, "Dockerfile"), "w+") do file
            for line in app.dockerfile_record
                write(file, line * "\n")
            end
            write(file, "# Switch to custom user" * '\n')
            write(file, "USER $(app.user)" * '\n')
        end

        # Build image
        Docker.image(app.shell,
            "build";
            tag = image_name(app),
            argument =  "." # Local Dockerfile in the temporary workspace
        )
    end
end

function container_shell_cmd(app::App, interactive::Bool = false)::String
    # Copy app.shell into a temporary Shell, and change its handler
    s = copy(app.shell)
    s.handler = (shell, cmd) -> cmd # trick to get the instanciated command and not running anything
    if interactive
        cmd = Docker.exec(s;
            argument = "$(container_name(app)) bash -l",
            user = app.user,
            tty = true,
            interactive = true
        )
    else
        cmd = Docker.exec(s;
            argument = "$(container_name(app))",
            user = app.user,
            tty = false,
            interactive = false
        )
    end
    CLI.close(s)
    return cmd
end

"""
Creates a `Shell` that is running `bash` inside `app`'s container.
!!!!! for some reason I cannot run docker exec in my CLI.Shell and keep it active (stdin is not a tty)
So we well have to do docker exec ... bach -c '<cmd>' each time !
"""
function container_shell(app::App)::CLI.Shell
    # Copy app.shell to connect it to the container
    s = Base.copy(app.shell)
    # Change s handler so that each command call is wrapper around a
    # docker exec ... bach -c '<cmd>' call! (may be slow)
    s.handler = (shell, cmd) -> begin
        app.shell.handler(shell, "$(container_shell_cmd(app, false)) bash -c '$cmd'")
    end
    #TODO: CLI.stringoutput and others do not call the handler !
    return s
end

"""

Run `cmd` inside `app`'s container (may be slow)
"""
function run(app::App, cmd::String, cb::Function)
    cb(app.shell, "$(container_shell_cmd(app, false)) bash -c '$cmd'")
end

# ----- Step 3: container setup ---
function setup_container(app::App)
    # Delete previous container if it exists
    destroy_container(app)

    # Start container (-l -> --login so that bash loads .bash_profile) 
    container_command = "$(image_name(app)) bash -l"
    Docker.run(app.shell;
        argument = container_command,
        name = container_name(app),
        hostname = app.appname,
        user = app.user,
        tty = true,
        detach = true
    )

    pkgs_done = Set{Package}()

    # Run packages's container step callback
    map(p -> begin
        if !(p in pkgs_done)
            if !isnothing(p.cbcontainer)
                p.cbcontainer(app)
            end
            push!(pkgs_done, p)
        end
        end, app.packages
    )

    println("Container for app $(app.appname) is ready, you can enter the container with command $(container_shell_cmd(app, true))")
end

function setup(app::App; clean_image = false)
    try
        init!(app)
        setup_host(app)
        setup_image(app, clean_image)
        setup_container(app)
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
        App, ENV, COPY, RUN, add_pkg!, setup, home, run
end