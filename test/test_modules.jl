
function get_command(s::CLI.Shell, cmd)
    return cmd
end

function strfilter(s::String)
    return filter(x -> !isspace(x), s)
end

function compare_string(a::String, b::String)
    return strfilter(a) == strfilter(b)
end

@testset "Test Docker Command Generation" begin
    s = CLI.LocalGitBash(;pwd = "~", env = Dict{String, String}(), handler = get_command)
    s["CL_DOCKER"] = "docker"
    cmd = Docker.run(s;
        argument = "ubuntu:lastet",
        name = "ContainerFromCLI",
        hostname = "MyApp",
        tty = true,
        detach = true
    )
    @test compare_string(cmd, "docker run --name ContainerFromCLI --hostname MyApp --tty --detach ubuntu:lastet")

    cmd = Docker.run(s;
        argument = "ubuntu:lastet",
        name = "ContainerFromCLI",
        hostname = "MyApp",
        tty = true,
        detach = false
    )
    @test compare_string(cmd, "docker run --name ContainerFromCLI --hostname MyApp --tty ubuntu:lastet")

    cmd = Docker.run(s, "--tty";
        argument = "ubuntu:lastet",
        name = "ContainerFromCLI",
        hostname = "MyApp",
    )
    @test compare_string(cmd, "docker run --tty --name ContainerFromCLI --hostname MyApp ubuntu:lastet")
end