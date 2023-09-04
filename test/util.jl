import CommandLine as CLI
import CommandLine.Docker as Docker


s = CLI.LocalGitBash(;pwd = "~", env = Dict{String, String}(), handler = CLI.showoutput)
s["CL_DOCKER"] = "docker"
# Example of use:
# Docker.image(s, "-h"; detach = true, port = "8001:22")

Docker.run(s, "ubuntu:22.04";
        name = "ContainerFromCLI",
        hostname = "MyApp",
        tty = true,
        detach = true
    )

@show Docker.container_exists(s, "ContainerFromCLI")