import CommandLine as CLI
import CommandLine.Docker as Docker
import CommandLine.ContainedEnv as ContainedEnv

"""
s = CLI.LocalGitBash(;pwd = "~", env = Dict{String, String}(), handler = CLI.showoutput)
s["CL_DOCKER"] = "docker"
# Example of use:
# Docker.image(s, "-h"; detach = true, port = "8001:22")

Docker.run(s;
    argument = "ubuntu:22.04",
    name = "ContainerFromCLI",
    hostname = "MyApp",
    tty = true,
    detach = true
)

#@show Docker.container_exists(s, "ContainerFromCLI")
@show Docker.containers(s)
"""

function print_input_output(s::CLI.Shell, cmd)
    println(cmd)
    CLI.showoutput(s, cmd)
end

s = CLI.LocalGitBash(;pwd = "~", env = Dict{String, String}(), handler = print_input_output)
s["CL_DOCKER"] = "docker"
# Required on GitBash, otherwise docker mounts does not work (path are messed up) !
CLI.run(s, "export MSYS_NO_PATHCONV=1")
app = ContainedEnv.DevApp(s; name = "julia", user = "aferreira", from = "ubuntu:22.04")
ContainedEnv.add_pkg!(app, ContainedEnv.JuliaLinux("1.9.1"))
ContainedEnv.add_mount!(app, Docker.Mount(:hostpath, @__DIR__, ContainedEnv.home(app)*"/mountdir"))
ContainedEnv.add_port!(app, Docker.Port("8080", "80"))
ContainedEnv.add_network!(app, Docker.Network("my_network"))
ContainedEnv.deploy!(app)
#ContainedEnv.container_running(app)