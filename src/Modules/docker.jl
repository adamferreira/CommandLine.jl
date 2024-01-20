module Docker
using JSON
using CommandLine.Paths
import CommandLine as CLI
"""
One must define the environment variable `CL_DOCKER` in a `Shell`
to be able to call the function of this module.


    Usage:  docker [OPTIONS] COMMAND

    A self-sufficient runtime for containers
    
    Common Commands:
      run         Create and run a new container from an image
      exec        Execute a command in a running container
      ps          List containers
      build       Build an image from a Dockerfile
      pull        Download an image from a registry
      push        Upload an image to a registry
      images      List images
      login       Log in to a registry
      logout      Log out from a registry
      search      Search Docker Hub for images
      version     Show the Docker version information
      info        Display system-wide information
    
    Management Commands:
      builder     Manage builds
      buildx*     Docker Buildx (Docker Inc., v0.11.2-desktop.1)
      compose*    Docker Compose (Docker Inc., v2.20.2-desktop.1)
      container   Manage containers
      context     Manage contexts
      dev*        Docker Dev Environments (Docker Inc., v0.1.0)
      extension*  Manages Docker extensions (Docker Inc., v0.2.20)
      image       Manage images
      init*       Creates Docker-related starter files for your project (Docker Inc., v0.1.0-beta.6)
      manifest    Manage Docker image manifests and manifest lists
      network     Manage networks
      plugin      Manage plugins
      sbom*       View the packaged-based Software Bill Of Materials (SBOM) for an image (Anchore Inc., 0.6.0)
      scan*       Docker Scan (Docker Inc., v0.26.0)
      scout*      Command line tool for Docker Scout (Docker Inc., 0.20.0)
      system      Manage Docker
      trust       Manage trust on Docker images
      volume      Manage volumes
    
    Swarm Commands:
      swarm       Manage Swarm
    
    Commands:
      attach      Attach local standard input, output, and error streams to a running container
      commit      Create a new image from a container's changes
      cp          Copy files/folders between a container and the local filesystem
      create      Create a new container
      diff        Inspect changes to files or directories on a container's filesystem
      events      Get real time events from the server
      export      Export a container's filesystem as a tar archive
      history     Show the history of an image
      import      Import the contents from a tarball to create a filesystem image
      inspect     Return low-level information on Docker objects
      kill        Kill one or more running containers
      load        Load an image from a tar archive or STDIN
      logs        Fetch the logs of a container
      pause       Pause all processes within one or more containers
      port        List port mappings or a specific mapping for the container
      rename      Rename a container
      restart     Restart one or more containers
      rm          Remove one or more containers
      rmi         Remove one or more images
      save        Save one or more images to a tar archive (streamed to STDOUT by default)
      start       Start one or more stopped containers
      stats       Display a live stream of container(s) resource usage statistics
      stop        Stop one or more running containers
      tag         Create a tag TARGET_IMAGE that refers to SOURCE_IMAGE
      top         Display the running processes of a container
      unpause     Unpause all processes within one or more containers
      update      Update configuration of one or more containers
      wait        Block until one or more containers stop, then print their exit codes
    
    Global Options:
          --config string      Location of client config files (default
                               "C:\\Users\\AdamFerreiraDaCosta\\.docker")
      -c, --context string     Name of the context to use to connect to the
                               daemon (overrides DOCKER_HOST env var and
                               default context set with "docker context use")
      -D, --debug              Enable debug mode
      -H, --host list          Daemon socket to connect to
      -l, --log-level string   Set the logging level ("debug", "info",
                               "warn", "error", "fatal") (default "info")
          --tls                Use TLS; implied by --tlsverify
          --tlscacert string   Trust certs signed only by this CA (default
                               "C:\\Users\\AdamFerreiraDaCosta\\.docker\\ca.pem")
          --tlscert string     Path to TLS certificate file (default
                               "C:\\Users\\AdamFerreiraDaCosta\\.docker\\cert.pem")
          --tlskey string      Path to TLS key file (default
                               "C:\\Users\\AdamFerreiraDaCosta\\.docker\\key.pem")
          --tlsverify          Use TLS and verify the remote
      -v, --version            Print version information and quit
    
    Run 'docker COMMAND --help' for more information on a command.
    
    For more help on how to use Docker, head to https://docs.docker.com/go/guides/
"""

# Docker SubCommands
SUB_COMMANDS = [
    :attach,	# Attach local standard input, output, and error streams to a running container
    :build,	    # Build an image from a Dockerfile
    :builder,	# Manage builds
    :checkpoint,# Manage checkpoints
    :commit,	# Create a new image from a container's changes
    :config,	# Manage Swarm configs
    :container,	# Manage containers
    :context,	# Manage contexts
    :cp,	    # Copy files/folders between a container and the local filesystem
    :create,	# Create a new container
    :diff,	    # Inspect changes to files or directories on a container's filesystem
    :events,	# Get real time events from the server
    :exec,	    # Execute a command in a running container
    :export,	# Export a container's filesystem as a tar archive
    :history,	# Show the history of an image
    :image,	    # Manage images
    :images,	# List images
    :import,	# Import the contents from a tarball to create a filesystem image
    :info,	    # Display system-wide information
    :inspect,	# Return low-level information on Docker objects
    :kill,	    # Kill one or more running containers
    :load,	    # Load an image from a tar archive or STDIN
    :login,	    # Log in to a registry
    :logout,	# Log out from a registry
    :logs,	    # Fetch the logs of a container
    :manifest,	# Manage Docker image manifests and manifest lists
    :network,	# Manage networks
    :node,	    # Manage Swarm nodes
    :pause,	    # Pause all processes within one or more containers
    :plugin,	# Manage plugins
    :port,	    # List port mappings or a specific mapping for the container
    :ps,	    # List containers
    :pull,	    # Download an image from a registry
    :push,	    # Upload an image to a registry
    :rename,	# Rename a container
    :restart,	# Restart one or more containers
    :rm,	    # Remove one or more containers
    :rmi,	    # Remove one or more images
    :run,	    # Create and run a new container from an image
    :save,	    # Save one or more images to a tar archive (streamed to STDOUT by default)
    :search,	# Search Docker Hub for images
    :secret,	# Manage Swarm secrets
    :service,	# Manage Swarm services
    :stack,	    # Manage Swarm stacks
    :start,	    # Start one or more stopped containers
    :stats,	    # Display a live stream of container(s) resource usage statistics
    :stop,	    # Stop one or more running containers
    :swarm,	    # Manage Swarm
    :system,	# Manage Docker
    :tag,	    # Create a tag TARGET_IMAGE that refers to SOURCE_IMAGE
    :top,	    # Display the running processes of a container
    :trust,	    # Manage trust on Docker images
    :unpause,	# Unpause all processes within one or more containers
    :update,	# Update configuration of one or more containers
    :version,	# Show the Docker version information
    :volume,	# Manage volumes
    :wait,	    # Block until one or more containers stop, then print their exit codes
    :buildx     # Docker 23.0: https://docs.docker.com/engine/deprecated/#legacy-builder-for-linux-images
]

# Define SubCommands calls as fonction of the module
for fct in SUB_COMMANDS
    #@eval function $(Symbol(fct, :_str))(s::CLI.Shell, args...; kwargs...)
    #    strfct = string($fct)
    #    return "$(s[:CL_DOCKER]) $strfct $(CLI.make_cmd(args...; kwargs...))"
    #end

    #@eval function $fct(s::CLI.Shell, args...; kwargs...)
    #    return CLI.run(s, $(Symbol(fct, :_str))(s, args...; kwargs...))
    #end

    @eval function $fct(args...; kwargs...)
        strfct = string($fct)
        return "docker $strfct $(CLI.make_cmd(args...; kwargs...))"
    end

    @eval function $fct(s::CLI.Shell, args...; kwargs...)
        strfct = string($fct)
        return CLI.run(s, "$(s[:CL_DOCKER]) $strfct $(CLI.make_cmd(args...; kwargs...))")
    end

    # Also export the function
    @eval export $(fct)#, $(Symbol(fct, :_str))
end


for fct in [:container, :image, :volume, :network]
    # Generalisation for 'ls' subfunctions with parametric filters, example:
    # function containers(s::CLI.Shell, filters::Pair{String, String}...)::Vector{Dict}
    #     out = CLI.checkoutput(s,
    #         container(
    #             "ls", "--all", map(f -> "--filter $(f.first)=$(f.second)", filters)...,
    #             ; format="'{{json .}}'"
    #         )
    #     )
    #     return JSON.parse.(out)
    # end
    #
    # function get_container(s::CLI.Shell, name::String)::Union{Nothing, Dict}
    #     elements = containers(s, "name" => name)
    #     return length(elements) == 0 ? nothing : elements[1]
    # end
    #
    # function container_exist(s::CLI.Shell, name::String)::Bool
    #     return !isnothing(get_container(s, name))
    # end
    #
    # export containers, get_container, container_exist
    # $(Symbol(fct, :s) creates the Symbol <fct>s
    # For example, :volume will become :volumes
    @eval function $(Symbol(fct, :s))(s::CLI.Shell, filters::Pair{String, String}...)::Vector{Dict}
        out = CLI.checkoutput(s,
            $(fct)(
                "ls", map(f -> "--filter $(f.first)=$(f.second)", filters)...,
                ; format="'{{json .}}'"
            )
        )
        return JSON.parse.(out)
    end

    @eval function $(Symbol(:get_, fct))(s::CLI.Shell, name::String)::Union{Nothing, Dict}
        # For some reasons, docker image ls --filter name=name does not work
        # and require --filter reference=name instead
        filter = Symbol($fct) == :image ? "reference" : "name"
        elements = $(Symbol(fct, :s))(s, filter => name)
        return length(elements) == 0 ? nothing : elements[1]
    end

    @eval function $(Symbol(fct, :_exist))(s::CLI.Shell, name::String)::Bool
        return !isnothing( $(Symbol(:get_, fct))(s, name) )
    end

    @eval export $(Symbol(fct, :s)), $(Symbol(:get_, fct)), $(Symbol(fct, :_exist))
end

function container_running(s::CLI.Shell, cname::String)::Bool
    status = Docker.containers(s, "name" => cname)
    return length(status) == 0 ? false : status[1]["State"] == "running"
end
export container_running

function json_version(s::CLI.Shell)::Dict
    vstr = CLI.checkoutput(s, version(format="'{{json .}}'"))
    return JSON.parse(vstr[1])
end

function client_version(s::CLI.Shell)::Tuple{Int,Int,Int}
    vjson = json_version(s)
    m = match(r"(?<MAJOR>\d*)\.(?<MINOR>\d*)\.(?<PATCH>\d*)", vjson["Client"]["Version"])
    return parse(Int, m["MAJOR"]), parse(Int, m["MINOR"]), parse(Int, m["PATCH"])
end
export client_version

"""
    Mount
(Docker only support posix path as src (host) paths)
- `type::Symbol`: Either `:hostpath` ou `:volume`
- `src::String`: Either a path on the host, or a volume name
- `target::String`: (Posix) path in the container filesystem
- `readonly::Bool`: Mount as readonly
- `driver::String`
- `opt::Vector{String}` Mount options (see Docker's --mount)
"""
struct Mount
    type::Symbol
    src::PosixPath
    # Docker requires <target> to be a posix path
    target::PosixPath
    readonly::Bool
    driver::String
    opt::Vector{String}

    function Mount(
        type, src, target
        ;
        readonly = false,
        driver = "local",
        opt = []
    )
        return new(
            type,
            PosixPath(typeof(src) == String ? Path(src) : src),
            PosixPath(typeof(target) == String ? Path(target) : target),
            readonly,
            driver,
            opt
        )
    end
end

function Base.string(m::Mount)::String
    # The syntax --mount src=<src>,target=<target>[,volume-driver=<driver>][,readonly][,volume-opt=<opt_i>]*
    #   Only works when <src> is a volume, thus we prefer the short format
    #   -v <src>:<target>[,ro]
    #   When <src> is a (host) path
    # Docker requires <target> to be a posix path
    short = (m.type == :hostpath)

    if short
        line = "-v $(m.src):$(m.target)" * (m.readonly ? ",ro" : "")
    else
        line = "--mount src=$(m.src),target=$(m.target),volume-driver=$(m.driver)"
        if m.readonly
            line = line * ",readonly"
        end
        if length(m.opt) > 0
            line = line * "," * Base.join(map(x -> "volume-opt=$x", m.opt), ",")
        end
    end
    return line
end
# Interpolation overloading
Base.show(io::IO, m::Mount) = print(io, Base.string(m))
export Mount


struct Port
    on_host::String
    on_container::String
    function Port(onhost, oncontainer)
        return new(onhost, oncontainer)
    end
end

function Base.string(p::Port)::String
    return "-p $(p.on_host):$(p.on_container)"
end
# Interpolation overloading
Base.show(io::IO, p::Port) = print(io, Base.string(p))
export Port


struct Network
    name::String
    function Network(name)
        return new(name)
    end
end
function Base.string(n::Network)::String
    return "--net $(n.name)"
end
# Interpolation overloading
Base.show(io::IO, n::Network) = print(io, Base.string(n))
export Network


# Todo: Docker container run should return a Shell{Bash, Docker}
# Or an attach fonction ?

end

"""
    TODO: Useless as s["CL_DOCKER"] = <path> is enought ?
"""
function DockerShell(s::Shell, dockerexe)
    # Shells connecting to docker containers are assumed to be bash shells
    # Firt, launch a copy of the host's Shell `s`, where we will launch docker
    dockershell = Shell{Bash, Docker}(
        s.cmd;
        pwd = s.pwd,
        env = copy(s.env),
        handler = s.handler
    )
    # Add a link to docjer exe in the Shell
    dockershell["CL_DOCKER"] = dockerexe
    return dockershell
end