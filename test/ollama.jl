using CommandLine.Paths
import CommandLine as CLI
import CommandLine.Docker as Docker
import CommandLine.ContainedEnv as ContainedEnv

function print_input_output(s::CLI.Shell, cmd)
    println("\$ ", cmd)
    CLI.showoutput(s, cmd)
end
s = CLI.LocalGitBash(;pwd = "~", env = Dict{String, String}(), handler = print_input_output)
s["CL_DOCKER"] = "docker"
# Required on GitBash, otherwise docker mounts does not work (path are messed up) !
CLI.run(s, "export MSYS_NO_PATHCONV=1")


function Ollama(model::String)::ContainedEnv.Package
    return ContainedEnv.Package(
        "ollama", "v0";
        requires = [
            # To download the install script
            ContainedEnv.BasePackage("curl"),
            # WARNING: Unable to detect NVIDIA GPU. Install lspci or lshw to automatically detect and install NVIDIA CUDA drivers
            # Ollama might not detect your hardware (GPU) without lspci installed
            ContainedEnv.BasePackage("pciutils"),
        ],
        install_image = app -> begin
            # See install doc here: https://github.com/jmorganca/ollama
            ContainedEnv.RUN(app,
                "curl https://ollama.ai/install.sh | sh",
                #"ollama pull $(model)"
            )
        end,
        install_container = app -> begin
            # Start the Ollama server inside the container
            CLI.run(app.contshell, "ollama serve")
        end
    )
end

app = ContainedEnv.DevApp(s; name = "chatbot", user = "aiuser", from = "ubuntu:22.04")
ContainedEnv.add_pkg!(app, Ollama("mistral"))
ContainedEnv.deploy!(app)