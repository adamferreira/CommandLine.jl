import CommandLine as CLI
import CommandLine.Docker as Docker
import CommandLine.ContainedEnv as ContainedEnv

function print_input_output(s::CLI.Shell, cmd)
    println(cmd)
    CLI.showoutput(s, cmd)
end

s = CLI.LocalGitBash(;pwd = "~", env = Dict{String, String}(), handler = print_input_output)
s["CL_DOCKER"] = "docker"

# App from Ubuntu image
app = ContainedEnv.App(s; name = "containedenvtest", user = "aferreira", from = "ubuntu:22.04")

# Basic packages that can be installed from image's package manager
cmake = ContainedEnv.BasePackage("cmake")
curl = ContainedEnv.BasePackage("curl")


# To illustrate how packages can have installation routines in the host, the image and the container
# We will make a fake package that will use all steps:


fakepkg1 = ContainedEnv.Package("fakepkg1", "v0";
    # Create a file locally
    install_host = app -> begin
        open(Base.joinpath(Base.pwd(), "FakeFile.txt"), "w+") do file
            write(file, "Hello from the container\n")
        end
    end,
    # Copy the newly created file into the image
    install_image = app -> begin
        ContainedEnv.COPY(app, Base.joinpath(Base.pwd(), "FakeFile.txt"), ContainedEnv.home(app))
    end,
    # Check that the file is in the contaier, and remove it locally!
    install_container = app -> begin
        Base.rm(Base.joinpath(Base.pwd(), "FakeFile.txt"))
        # At this step, app.contshell should point to a Shell session IN the container
        filecontent = CLI.stringoutput(app.contshell, "cat ~/FakeFile.txt")
        if filecontent == "Hello from the container"
            println("File successfully found in the container !")
        end
    end
)
ContainedEnv.add_pkg!(app, fakepkg1)
# Mount volumes
ContainedEnv.add_mount!(app, Docker.Mount(:hostpath, @__DIR__, ContainedEnv.home(app)*"/mountdir"))
# Ports
ContainedEnv.add_port!(app, Docker.Port("8080", "80"))
# Networks
#ContainedEnv.add_network!(app, Docker.Network("my_network"))

# Package that depends on other packages


# Setup app
ContainedEnv.deploy!(app)