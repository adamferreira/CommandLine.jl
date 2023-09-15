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

function testContainedEnv()
    s = CLI.LocalGitBash(;pwd = "~", env = Dict{String, String}(), handler = print_input_output)
    s["CL_DOCKER"] = "docker"
    app = ContainedEnv.App(s; name = "containedenvtest", user = "aferreira", from = "ubuntu:22.04")


    cmake = ContainedEnv.BasePackage("cmake")
    curl = ContainedEnv.BasePackage("curl")
    cppdev = ContainedEnv.Package("cppdev", "v1.0.0"; requires = [cmake, curl])

    ContainedEnv.add_pkg!(app, cppdev)


    ContainedEnv.setup(app)
end

testContainedEnv()