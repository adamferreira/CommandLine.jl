import CommandLine as CLI
import CommandLine.Docker as Docker


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

user = "aferreira"
s = """
useradd -r -m -U -G sudo -d /home/$user -s /bin/bash -c \"Docker SGE user\" $user"
echo \"$user ALL=(ALL:ALL) NOPASSWD: ALL\" | sudo tee /etc/sudoers.d/$user
chown -R $user /home/$user
mkdir /home/$user/projects
chown -R $user /home/$user/*
"""