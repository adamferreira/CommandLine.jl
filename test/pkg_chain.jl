import CommandLine as CLI
import CommandLine.Docker as Docker
import CommandLine.ContainedEnv as ContainedEnv


s = CLI.LocalGitBash(;pwd = "~", env = Dict{String, String}())
s["CL_DOCKER"] = "docker"
# Required on GitBash, otherwise docker mounts does not work (path are messed up) !
CLI.run(s, "export MSYS_NO_PATHCONV=1")
app = ContainedEnv.DevApp(s; name = "pkg_chain", user = "aferreira", from = "ubuntu:22.04")

function test_pkg(name, deps...)
    return ContainedEnv.Package(
        "package", name; requires = collect(deps),
        install_host = app -> begin
            println("Installing package $(name)")
        end
    )
end

p1 = test_pkg("1")
p2 = test_pkg("2")
p3 = test_pkg("3", p1, p2)
p4 = test_pkg("4", p2)

ContainedEnv.add_pkg!(app, p2)
ContainedEnv.add_pkg!(app, p3)
ContainedEnv.add_pkg!(app, p4)
ContainedEnv.deploy!(app)