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

    function App(
        s::CLI.Shell;
        name,
        user,
        from)
    
        app = new(name, user, from, s, ["FROM $from"], [])
        # The begining of every containedenv is the same
        COMMENT(app, "Setting up global env vars")
        ENV(app, "USER", user)
        ENV(app, "HOME", raw"/home/${USER}")
        COMMENT(app, "Updating package manager")
        RUN(app, "apt-get update -y", "apt-get upgrade -y")
        COMMENT(app, "Setting up $user as a sudo user and create its home")
        RUN(
            app,
            "useradd -r -m -U -G sudo -d /home/$user -s /bin/bash -c 'Docker SGE user' $user",
            "echo \"$user ALL=(ALL:ALL) NOPASSWD: ALL\" | sudo tee /etc/sudoers.d/$user",
            "chown -R $user /home/$user",
            "mkdir /home/$user/projects",
            "chown -R $user /home/$user/*"
        )
    
        return app
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

    container["State"] == "exited" || @error("Could not stop container $(container_name(app))")
    # Destroy the container
    Docker.rm(app.shell, container_name(app))
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
function ENV(d::App, var, val)
    push!(d.dockerfile_record, "ENV $var=$val")
end

function COPY(d::App, from, to)
    from = CLI.cygpath(app.shell, from, "-u")
    @assert CLI.isdir(app.shell, from) || CLI.isfile(app.shell, from)
    push!(d.dockerfile_record, "COPY $from $to")
end

function RUN(d::App, cmds::String...)
    # Pack each commands into one RUN command to avoir having to much layers
    run_cmd = Base.join(vcat(cmds...), " ;\\ \n\t")
    push!(d.dockerfile_record, "RUN $run_cmd")
end

function COMMENT(d::App, line::String)
    push!(d.dockerfile_record, "# $line")
end

function COMMENT(d::App, lines::String...)
    map(l -> COMMENT(d, l), lines...)
end




# ----- Step 1: local setup ---
function setup_host(app::App)
    pkgs_done = Set{Package}()
end

# ----- Step 2: image setup ---
function setup_image(app::App)
    pkgs_done = Set{Package}()

    # Delete previous image if it exists
    destroy_image(app)
    return nothing

    # Run base packages installation in one line to save layer count
    # Only install package once!
    map(p -> begin
        push!(pkgs_done, p)
        end, filter(p -> p.tag == "base", app.packages)
    )
    COMMENT(app, "Installing base packages")
    RUN(app, "apt-get install -y " * Base.join(map(p -> p.name, collect(pkgs_done)), ' '))

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

    # Create tempory dir and Dockerfile
    dockerfile_dir = Base.pwd()
    dockerfile = Base.joinpath(dockerfile_dir, "Dockerfile")

    # Write Dockerfile
    open(dockerfile, "w+") do file
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
        argument =  CLI.cygpath(app.shell, dockerfile_dir, "-u") # Local Dockerfile dir
    )

    # Destroy temporary data
    CLI.rm(app.shell, CLI.cygpath(app.shell, dockerfile, "-u"))
    @assert !CLI.isfile(app.shell, CLI.cygpath(app.shell, dockerfile, "-u"))
end

# ----- Step 3: container setup ---
function setup_container(app::App)
    pkgs_done = Set{Package}()
end

function setup(app::App)
    #setup_host(app)
    setup_image(app)
    #setup_container(app)
end

export  Package, BasePackage,
        App, ENV, COPY, RUN, add_pkg!, setup
end