module Docker
using JSON
import CommandLine as CLI
"""
One must define the environment variable `CL_DOCKER` in a `Shell`
to be able to call the function of this module.
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
    :wait	    # Block until one or more containers stop, then print their exit codes
]

# Define SubCommands calls as fonction of the module
for fct in SUB_COMMANDS
    @eval function $(Symbol(fct, :_str))(s::CLI.Shell, args...; kwargs...)
        strfct = string($fct)
        return "$(s[:CL_DOCKER]) $strfct $(CLI.make_cmd(args...; kwargs...))"
    end

    @eval function $fct(s::CLI.Shell, args...; kwargs...)
        return CLI.run(s, $(Symbol(fct, :_str))(s, args...; kwargs...))
    end

    # Also export the function
    @eval export $(fct), $(Symbol(fct, :_str))
end

"""
    containers(s::CLI.Shell, filter::String)::Vector{Dict}
filter="name=cntname"
"""
function containers(s::CLI.Shell, filter::String)::Vector{Dict}
    lock(s.run_mutex)
    # Silent calls for now and get output (save current handler)
    savefct = s.handler
    s.handler = CLI.checkoutput

    # Scrap outputs of `docker container ls`
    out = container(s, "ls", "--all"; format="'{{json .}}'", filter=filter)

    # Reset Shell to original state
    s.handler = savefct
    unlock(s.run_mutex)

    return JSON.parse.(out)
end
export containers

function container_exists(s::CLI.Shell, cname::String)
    return length(containers(s, "name=$(cname)")) > 1
end
export container_exists

function container_running(s::CLI.Shell, cname::String)::Bool
    status = Docker.containers(s, "name=$(cname)")
    return length(status) == 0 ? false : status[1]["State"] == "running"
end
export container_running

function networks(s::CLI.Shell)::Vector{Dict}
    # Silent calls for now and get output (save current handler)
    savefct = s.handler
    s.handler = CLI.checkoutput
    out = network(s, "ls"; format="'{{json .}}'")
    # Reset Shell to original state
    s.handler = savefct
    #TODO: encapsulate handler switch in a method call 'with handler?'
    return JSON.parse.(out)
end

function get_image(s::CLI.Shell, imgname::String)::Union{Nothing, Dict}
    lock(s.run_mutex)
    # Silent calls for now and get output (save current handler)
    savefct = s.handler
    s.handler = CLI.checkoutput

    # Scrap outputs of `docker image ls`
    out = images(s, imgname; format="'{{json .}}'")

    if length(out) == 0 
        return nothing
    end

    # Reset Shell to original state
    s.handler = savefct
    unlock(s.run_mutex)

    return JSON.parse(out[1])
end
export get_image

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
    src::String
    target::String
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
        return new(type, src, target, readonly, driver, opt)
    end
end

function mountstr(s::CLI.Shell, m::Mount)::String
    # Docker only support posix path as src (host) paths
    src = CLI.cygpath(s, m.src, "-u")
    target = CLI.cygpath(s, m.target, "-u")
    # The syntax --mount src=<src>,target=<target>[,volume-driver=<driver>][,readonly][,volume-opt=<opt_i>]*
    #   Only works when <src> is a volume, thus we prefer the short format
    #   -v <src>:<target>[,ro]
    #   When <src> is a (host) path
    short = (m.type == :hostpath)# || (CLI.isdir(s, src) || CLI.isfile(s, src))

    if short
        line = "-v $(src):$(target)" * (m.readonly ? ",ro" : "")
    else
        line = "--mount src=$src,target=$target,volume-driver=$(m.driver)"
        if m.readonly
            line = line * ",readonly"
        end
        if length(m.opt) > 0
            line = line * "," * Base.join(map(x -> "volume-opt=$x", m.opt), ",")
        end
    end
    return line
end
export Mount, mountstr


struct Port
    on_host::String
    on_container::String
    function Port(onhost, oncontainer)
        return new(onhost, oncontainer)
    end
end

function portstr(s::CLI.Shell, m::Port)::String
    return "-p $(m.on_host):$(m.on_container)"
end
export Port, portstr


struct Network
    name::String
    function Network(name)
        return new(name)
    end
end
function networkstr(s::CLI.Shell, n::Network)::String
    return "--net $(n.name)"
end
export Network, networkstr


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