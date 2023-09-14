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
    cbhost::Function
    cbimgage::Function
    cbcontainer::Function
end

function Package(
    name::String,
    tag::String;
    install_host::Function = app -> nothing,
    install_image::Function = app -> nothing,
    install_container::Function = app -> nothing
)
    return new(name, tag, install_host, install_image, install_container)
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
    dependencies::Dict{Package, Set{Package}}

    function App(
        s::CLI.Shell;
        name,
        user,
        from)
    
        app = new(name, user, from, s, PackageManager(from), ["FROM $from"])
        # The begining of every containedenv is the same
        # Setting up `user` as a sudo user and create its home
        RUN(
            app,
            "useradd -r -m -U -G sudo -d /home/$user -s /bin/bash -c \"Docker SGE user\" $user",
            "echo \"$user ALL=(ALL:ALL) NOPASSWD: ALL\" | sudo tee /etc/sudoers.d/$user",
            "chown -R $user /home/$user",
            "mkdir /home/$user/projects",
            "chown -R $user /home/$user/*"
        )
    
        return app
    end
end

function add_pkg!(app::App, p::Package; requires::Vector{Package} = [])
    app.dependencies[p] = Set{Package}(requires)
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
    run_cmd = Base.join(vcat(cmds...), "&& \\ \t")
    push!(d.dockerfile_record, "RUN $run_cmd")
end




# ----- Step 1: local setup ---
function setup_host(app::App)
    pkgs_done = Set{Package}()
end

# ----- Step 2: image setup ---
function setup_image(app::App)
    # write in file -> push!(d.dockerfile_record, "FROM $(app.baseimg)")
    pkgs_done = Set{Package}()
end

# ----- Step 3: container setup ---
function setup_container(app::App)
    pkgs_done = Set{Package}()
end

function setup(app::App)
    setup_host(app)
    setup_image(app)
    setup_container(app)
end

export  Package, BasePackage,
        App, ENV, COPY, RUN, setup
end