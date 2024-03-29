
function get_command(s::CLI.Shell, cmd)
    return cmd
end

function strfilter(s::String)
    return filter(x -> !isspace(x), s)
end

function compare_string(a::String, b::String)
    @test strfilter(a) == strfilter(b)
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
    compare_string(cmd, "docker run --name ContainerFromCLI --hostname MyApp --tty --detach ubuntu:lastet")

    # Now without passing the shell (just generating the commad without executing it)
    cmd = Docker.run(
        argument = "ubuntu:lastet",
        name = "ContainerFromCLI",
        hostname = "MyApp",
        tty = true,
        detach = true
    )
    compare_string(cmd, "docker run --name ContainerFromCLI --hostname MyApp --tty --detach ubuntu:lastet")

    cmd = Docker.run(s;
        argument = "ubuntu:lastet",
        name = "ContainerFromCLI",
        hostname = "MyApp",
        tty = true,
        detach = false
    )
    compare_string(cmd, "docker run --name ContainerFromCLI --hostname MyApp --tty ubuntu:lastet")

    cmd = Docker.run("--tty";
        argument = "ubuntu:lastet",
        name = "ContainerFromCLI",
        hostname = "MyApp",
    )
    compare_string(cmd, "docker run --tty --name ContainerFromCLI --hostname MyApp ubuntu:lastet")

    # -------- Mounts --------
    # Short syntax
    m = Docker.Mount(:hostpath, pp"path/on/host", pp"path/in/container")
    compare_string("$m", "-v path/on/host:path/in/container")
    m = Docker.Mount(:hostpath, pp"path/on/host", pp"path/in/container"; readonly = true)
    compare_string("$m", "-v path/on/host:path/in/container,ro")
    # Long syntax
    m = Docker.Mount(:volume, p"myvolume", pp"path/in/container")
    compare_string("$m", "--mount src=myvolume,target=path/in/container,volume-driver=local")
    m = Docker.Mount(:volume, p"myvolume", pp"path/in/container"; readonly = true)
    compare_string("$m", "--mount src=myvolume,target=path/in/container,volume-driver=local,readonly")
    m = Docker.Mount(:volume, p"myvolume", pp"path/in/container"; readonly = true, opt = ["opt1", "opt2"])
    compare_string("$m", "--mount src=myvolume,target=path/in/container,volume-driver=local,readonly,volume-opt=opt1,volume-opt=opt2")
    # Non posix paths
    m = Docker.Mount(:hostpath, p"path\on\host", pp"path/in/container")
    compare_string("$m", raw"-v path\on\host:path/in/container")
    m = Docker.Mount(:hostpath, p"path\on\host", p"path\in\container")
    compare_string("$m", raw"-v path\on\host:path/in/container")
end

@testset "Test Git Command Generation" begin
    compare_string(Git.status(), "git status")
    compare_string(
        Git.clone(branch="debug", depth=2, sparse=true, argument="my_repo"),
        "git clone --branch debug --depth 2 --sparse my_repo"
    )
end