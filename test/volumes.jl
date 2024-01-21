using CommandLine.Paths
import CommandLine as CLI
import CommandLine.Docker as Docker
import CommandLine.ContainedEnv as ContainedEnv

"""
Small example that creates a volume
Writter to into using an `App`
and read in from another `App`
Clean apps and volumes when its done

TODO: The file created in the volume is created on the name of the user?
TODO: remove the need to 'sudo' call writting to the volume
"""

function print_input_output(s::CLI.Shell, cmd)
    println("\$ ", cmd)
    CLI.showoutput(s, cmd)
end
s = CLI.LocalGitBash(;pwd = "~", env = Dict{String, String}(), handler = print_input_output)
s["CL_DOCKER"] = "docker"
# Required on GitBash, otherwise docker mounts does not work (path are messed up) !
CLI.run(s, "export MSYS_NO_PATHCONV=1")



volumetest = Docker.Mount(:volume, "myvolume", "/opt/mountdir")
filetest = Paths.joinpath(volumetest.target, "monvolume.txt")
app_writter = ContainedEnv.DevApp(s; name = "writter", user = "root", from = "ubuntu:22.04")
app_reader = ContainedEnv.DevApp(s; name = "reader", user = "root", from = "ubuntu:22.04")


# Docker will automatically creates the volume the first time it is used by a container (in the docker run command)
ContainedEnv.add_mount!(app_writter, volumetest)
ContainedEnv.add_mount!(app_reader, volumetest)

# Create Writter container/image and shared volume
@assert !Docker.volume_exist(s, "myvolume")
ContainedEnv.deploy!(app_writter)
@assert Docker.volume_exist(s, "myvolume")
@assert ContainedEnv.image_exist(app_writter)
@assert ContainedEnv.container_running(app_writter)

# Write a file into the volume and clean writter image/container
CLI.run(app_writter.contshell, "echo 'Hello World' >> $(filetest)")
@assert CLI.isfile(app_writter.contshell, "$(filetest)")
ContainedEnv.clean_all!(app_writter)
@assert !ContainedEnv.image_exist(app_writter)
@assert !ContainedEnv.container_running(app_writter)

# Launch reader App and look into the shared volume
@assert Docker.volume_exist(s, "myvolume")
ContainedEnv.deploy!(app_reader)
@assert ContainedEnv.image_exist(app_reader)
@assert ContainedEnv.container_running(app_reader)
@assert CLI.isfile(app_reader.contshell, "$(filetest)")
content = CLI.checkoutput(app_reader.contshell, "cat $(filetest)")
@assert content[1] == "Hello World"
ContainedEnv.clean_all!(app_reader)
@assert !ContainedEnv.image_exist(app_reader)
@assert !ContainedEnv.container_running(app_reader)

# Now we can delete the volume
Docker.volume(s, "rm myvolume")
@assert !Docker.volume_exist(s, "myvolume")



#@show Docker.volumes(s)
#@show Docker.get_volume(s, "myvolume")
#@show Docker.volume_exist(s, "myvolume")
@show content