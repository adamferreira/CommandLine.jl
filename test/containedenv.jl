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
    # Check that is file is in the contaier, and remove it locally!
    install_container = app -> begin
        Base.rm(Base.joinpath(Base.pwd(), "FakeFile.txt"))
        filecontent = ContainedEnv.run(app, "cat ~/FakeFile.txt", CLI.stringoutput)
        if filecontent == "Hello from the container"
            println("File successfully found in the container !")
        end
    end
)
ContainedEnv.add_pkg!(app, fakepkg1)

# Package that depends on other packages

# Setup app
ContainedEnv.setup(app)