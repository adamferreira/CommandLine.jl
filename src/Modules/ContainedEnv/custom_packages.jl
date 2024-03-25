
function JuliaLinux(version::String = "1.8.0-rc1")::Package
    # SOURCE: https://github.com/docker-library/julia/blob/3eb14343427c06437c5eda730ce8df1aeff5eb36/1.8-rc/bullseye/Dockerfile
    # For example 1.8.0-rdc -> NAME = "-rdc"
    m = match(r"(?<MAJOR>\d*)\.(?<MINOR>\d*)\.(?<PATCH>\d*)(?<NAME>\-[\w]*)*", version)
    short_version = m["MAJOR"] * '.' * m["MINOR"]
    sha256_url = "https://julialang-s3.julialang.org/bin/checksums/julia-$(version).sha256"
    # Mapping sha256 and julia binaries url per architectures
    arch_shas = Dict()

    function on_host(app::App)
        # Get sha256 from Julia's server corresponding to the version
        # Each line have the sha256 and the archive name for each architectures and OS
        # File Sample:
        # bed81bb5e2cd60abb824b40cbb1ed2f27c9f974dfd7fbc43ce1684e5462bae2b  julia-1.8.0-rc1-linux-i686.tar.gz
        # a47efddaaccb424dad6499f870ab7f792c50827d23cc64cb9873280318337966  julia-1.8.0-rc1-linux-x86_64.tar.gz
        # 469382fe705de0cf0eb9db352c85db8f9aa5d406babbdf4fa39e1815ae9260f9  julia-1.8.0-rc1-mac64.dmg
        # c690fcd27c1f901568ff0827bbf3b337056b8254d33f2bcc0575bbfda9a2fd3a  julia-1.8.0-rc1-mac64.tar.gz
        # We filter for Linux here
        shas = filter(line -> occursin("linux", line), CLI.checkoutput(app.hostshell, "curl $sha256_url"))
        # Map archives names to corresponding sha256
        shas = Dict(map(line -> split(line, "  ")[2] => split(line, "  ")[1], shas))
        # Map archives urls and sha256 per architectures
        arch_shas[:amd64] = Dict(
            :url => "https://julialang-s3.julialang.org/bin/linux/x64/$short_version/julia-$(version)-linux-x86_64.tar.gz",
            :sha256 => shas["julia-$(version)-linux-x86_64.tar.gz"]
        )
        arch_shas[:arm64] = Dict(
            :url => "https://julialang-s3.julialang.org/bin/linux/aarch64/$short_version/julia-$(version)-linux-aarch64.tar.gz",
            :sha256 => shas["julia-$(version)-linux-aarch64.tar.gz"]
        )
        arch_shas[:i386] = Dict(
            :url => "https://julialang-s3.julialang.org/bin/linux/x86/$short_version/julia-$(version)-linux-i686.tar.gz",
            :sha256 => shas["julia-$(version)-linux-i686.tar.gz"]
        )
    end

    function on_image(app::App)
        COMMENT(app, "source : https://github.com/docker-library/julia/blob/3eb14343427c06437c5eda730ce8df1aeff5eb36/1.8-rc/bullseye/Dockerfile")
        ENV(app, "JULIA_PATH", "/usr/local/julia")
        ENV(app, "PATH", raw"$JULIA_PATH/bin:$PATH")
        ENV(app, "JULIA_VERSION", version)
        COMMENT(app, "https://julialang.org/juliareleases.asc")
        COMMENT(app, "Julia (Binary signing key) <buildbot@julialang.org>")
        ENV(app, "JULIA_GPG", "3673DF529D9049477F76B37566E3C7DC03D6E495")

        INSTALL = """
        set -eux; \\
            \\
            savedAptMark="\$(apt-mark showmanual)"; \\
            arch="\$(dpkg --print-architecture)"; \\
            case "\$arch" in \\
                'amd64') \\
                    url='$(arch_shas[:amd64][:url])'; \\
                    sha256='$(arch_shas[:amd64][:sha256])'; \\
                    ;; \\
                'arm64') \\
                    url='$(arch_shas[:arm64][:url])'; \\
                    sha256='$(arch_shas[:arm64][:sha256])'; \\
                    ;; \\
                'i386') \\
                    url='$(arch_shas[:i386][:url])'; \\
                    sha256='$(arch_shas[:i386][:sha256])'; \\
                    ;; \\
                *) \\
                    echo >&2 "error: current architecture (\$arch) does not have a corresponding Julia binary release"; \\
                    exit 1; \\
                    ;; \\
            esac; \\
            \\
            curl -fL -o julia.tar.gz.asc "\$url.asc"; \\
            curl -fL -o julia.tar.gz "\$url"; \\
            \\
            echo "\$sha256 *julia.tar.gz" | sha256sum --strict --check -; \\
            \\
            export GNUPGHOME="\$(mktemp -d)"; \\
            gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "\$JULIA_GPG"; \\
            gpg --batch --verify julia.tar.gz.asc julia.tar.gz; \\
            command -v gpgconf > /dev/null && gpgconf --kill all; \\
            rm -rf "\$GNUPGHOME" julia.tar.gz.asc; \\
            \\
            mkdir "\$JULIA_PATH"; \\
            tar -xzf julia.tar.gz -C "\$JULIA_PATH" --strip-components 1; \\
            rm julia.tar.gz; \\
            \\
            apt-mark auto '.*' > /dev/null; \\
            [ -z "\$savedAptMark" ] || apt-mark manual \$savedAptMark; \\
            apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \\
            \\
            # smoke test
            julia --version
        """

        RUN(app, INSTALL)
    end

    return Package(
        "julia", version;
        install_host = on_host,
        install_image = on_image,
        requires = [
            BasePackage("gnupg"), BasePackage("dirmngr"), BasePackage("curl")
        ]
    )
end

function __GitHubRepo(
    repo_url::String, user::String, usermail::String, github_token::String;
    clone_on::Symbol = :image,
    workspace::String = "~/projects",
)::Package
    on_host = nothing
    on_image = nothing
    on_container = nothing

    repo_name = replace(Base.basename(repo_url), ".git" => "")
    #TODO support \\?
    repo_dest = "$(workspace)/$(repo_name)"
    credentials_file = "$(repo_dest)/.git/.my_gh_credentials"

    # TODO: handle repo on host
    on_host = app -> begin

    end

    if clone_on == :image
        on_image = app -> begin
            RUN(
                app,
                # Clone repo in image
                "git clone $(repo_url) $(repo_dest)",
                # Trust repo and user
                "git config --global --add safe.directory $(repo_dest)",
                "chown -R $(app.user) $(repo_dest)",
                # Configure user credentials
                "cd $(repo_dest)",
                "git config --local user.name $(user)",
                "git config --local user.email $(usermail)",
                # Configure credentials file location
                "git config --local credential.helper 'store --file $(credentials_file)'"
            )
        end
    end

    on_container = app -> begin
        # Create a git credentials file from the github token as runtime inside the container
        # There is no trace of the token in the image!
        CLI.checkoutput(app.contshell, "echo 'https://$(user):$(github_token)@github.com' >> $(credentials_file)")
    end

    return Package(
        # Use repository URL as uuid
        "GitHubRepo", "$(repo_url)";
        install_host = on_host,
        install_image = on_image,
        install_container = on_container,
        requires = [
            BasePackage("git"), BasePackage("ca-certificates")
        ]
    )
end

# TODO: handle credential file
function GitRepo(
    repo_url::String;
    clone_root::AbstractPath,
    git_user::String = "",
    git_usermail::String = "",
    github_token::String = "",
    clone_with_name::String = "",
    clone_on::Symbol = :host, #[:host, :image, :container]
)::Package
    on_host = nothing
    on_image = nothing
    on_container = nothing
    repo_name = clone_with_name == "" ? replace(Base.basename(repo_url), ".git" => "") : clone_with_name
    repo_dest = Paths.joinpath(clone_root, repo_name)

    # If the git reposity is a github repo, we format the repo url to take into account the username
    # And eventually the token
    if occursin("github.com", repo_url)
        if github_token != ""
            header = "$(git_user):$(github_token)"
        else
            header = "$(git_user)"
        end
        formatted_repo_url = replace(repo_url, "github.com" => "$(header)@github.com")
    else
        formatted_repo_url = repo_url
    end

    tape_record = []
    # Clone repo in image
    push!(tape_record, "cd $(clone_root)")
    push!(tape_record, "<GIT> clone $(formatted_repo_url) $(repo_name)")
    # Trust repo and user
    push!(tape_record, "<GIT> config --global --add safe.directory $(repo_dest)")
    # Configure user credentials
    push!(tape_record, "cd $(repo_dest)")
    if git_user != ""
        push!(tape_record, "<GIT> config --local user.name \"$(git_user)\"")
    end
    if git_usermail != ""
        push!(tape_record, "<GIT> config --local user.email $(git_usermail)")
    end

    if clone_on == :host
        @error "Cloning git repository on host is not yet supported"
        on_host = app -> begin
            @assert CLI.isdir(app.hostshell, clone_root)
            # Instanciate git command
            record = map(r -> replace(r, "<GIT>" => app.hostshell["CL_GIT"]), tape_record)
            # Excecute all the commands as docker RUN commands
            map(cmd -> CLI.run(app.hostshell, cmd), record)
        end
    end
    
    if clone_on == :image
        @warn "Cloning on image is not recommended"
        on_image = app -> begin
            # Instanciate git command
            record = map(r -> replace(r, "<GIT>" => "git"), tape_record)
            # Add user rights to the newly created repo
            push!(record, "chown -R $(app.user) $(repo_dest)")
            RUN(app, record...) 
        end
    end

    if clone_on == :container
        on_container = app -> begin
            # Instanciate git command
            record = map(r -> replace(r, "<GIT>" => "git"), tape_record)
            # Add user rights to the newly created repo (this command takes priority)
            # TODO: keep sudo calls bellow ? (volumes are created by 'root', then a user on container would not have access)
            if !CLI.isdir(app.contshell, repo_dest)
                record = vcat("sudo mkdir $(repo_dest)", "sudo chown -R $(app.user) $(repo_dest)", record)
            end
            # Excecute all the commands as bash calls
            map(cmd -> CLI.run(app.contshell, cmd), record)
        end
    end

    return Package(
        # Use repository URL as uuid
        "GitRepo", "$(repo_url)";
        install_host = on_host,
        install_image = on_image,
        install_container = on_container,
        requires = [
            BasePackage("git"), BasePackage("ca-certificates")
        ]
    )
end
export GitRepo

function CommandLineDev(user::String, usermail::String, github_token::String)::Package
    return __GitHubRepo(
        "https://github.com/adamferreira/CommandLine.jl.git",
        user, usermail, github_token;
        clone_on = :image,
        workspace = "~/projects"
    )
end

"""
    Mount the given SHH keypair into ~/.shh within the container as local mounts
"""
function MountedSSHKeys(local_pub, local_priv, local_known_hosts = nothing)
    uuid = Base.hash(Base.hash("$local_pub"), Base.hash("$local_priv"))
    return Package(
        "MountedSSHKeys", string(uuid); requires = [],
        install_host = app -> begin
            # Check on host that the keys indeed exists
            #@assert CLI.isfile(app.hostshell, local_pub)
            #@assert CLI.isfile(app.hostshell, local_priv)
            # Mount keys to the app's home
            cont_pub = Paths.joinpath(home(app), ".ssh", CLI.basename(app.hostshell, PosixPath(local_pub)))
            cont_priv = Paths.joinpath(home(app), ".ssh", CLI.basename(app.hostshell, PosixPath(local_priv)))
            add_mount!(app, Docker.Mount(:hostpath, local_pub, cont_pub))
            add_mount!(app, Docker.Mount(:hostpath, local_priv, cont_priv))
            # Include known_hosts file if requested
            if !isnothing(local_known_hosts)
                cont_known_hosts = Paths.joinpath(home(app), ".ssh", CLI.basename(app.hostshell, PosixPath(local_known_hosts)))
                add_mount!(app, Docker.Mount(:hostpath, local_known_hosts, cont_known_hosts))
            end
        end
    )
end
export MountedSSHKeys

"""
    git_repositories = [
        (repo_url = https://github.com/adamferreira/CommandLine.jl.git, git_user = "toto"),
        (...)
    ]
"""
function create_volume_with_repos(
    shell::CLI.Shell,
    volume::Docker.Mount,
    owner::String = "root",
    git_repositories::Vector{<:NamedTuple} = [],
    ssh_pub::Union{Nothing, AbstractPath} = nothing,
    ssh_priv::Union{Nothing, AbstractPath} = nothing,
    known_hosts::Union{Nothing, AbstractPath} = nothing
)
    vol_name = volume.src
    vol_mountpoint = volume.target
    if Docker.volume_exist(shell, "$(vol_name)")
        @warn "Volume $(vol_name) already exists, exiting procedure :create_volume_with_repos"
        return nothing
    end

    # Create a subapp to clone the repositories into the newly created volume
    gitapp = DevApp(shell, name = "gitapp", user = owner, from = "ubuntu:22.04")

    # Mount SHH keys (and known_hosts file) to clone the repositories if needed
    if !isnothing(ssh_pub) && !isnothing(ssh_priv)
        add_pkg!(gitapp, MountedSSHKeys(ssh_pub, ssh_priv, known_hosts))
    end

    # Add all repo to be cloned as packages
    map(
        args -> begin
            add_pkg!(gitapp,
                # GitRepo have 'git' and 'ca-certificates' as dependencies
                GitRepo(
                    args[:repo_url];
                    # clone the repository into the volume's target
                    clone_root = vol_mountpoint,
                    git_user = args[:git_user],
                    git_usermail = args[:git_usermail],
                    clone_with_name = args[:clone_with_name],
                    # Only chose to clone on :container as we are using the subapp to write in the volume
                    clone_on = :container,
                    # Forward token
                    github_token = args[:github_token]
                )
            )
        end
    , git_repositories)

    # Mount given volume to the subapp
    add_mount!(gitapp, volume)

    # Start subapp work
    deploy!(gitapp; regenerate_image = true)

    # Destroy subapp entirely
    clean_all!(gitapp)
end
export create_volume_with_repos

"""
Mount a volume to ~/.vscode-server in a container.
when attaching VSCode to a container and installing extensions, all will be installed in the volume instead of the container.
This will allow persistance of VSCode extension and data accros containers, even if they stop.
"""
function VSCodeServer()
    vserver = app -> Paths.joinpath(ContainedEnv.home(app), ".vscode-server")

    return ContainedEnv.Package(
        "vscode-server", "v0"; requires = [],
        install_image = app -> begin
            # Pre-create dir with open access as VSCode need access to .vscode-server
            ContainedEnv.RUN(app, "mkdir $(vserver(app))", "chmod 777 $(vserver(app))")
        end,
        install_host = app -> begin
            ContainedEnv.add_mount!(app, Docker.Mount(:volume, "vscode-server", vserver(app)))
        end
    )
end
export VSCodeServer

"""
    Get profiling graph using gprof2dot standalone script from: https://github.com/jrfonseca/gprof2dot.
    This requires graphviz to convert generated dot file to image.
    Callgrind is used for profiling.
"""
function CodeProfiler()
    return ContainedEnv.Package(
        "vscode-CodeProfiler", "v0"; requires = [
            ContainedEnv.BasePackage("python3"), ContainedEnv.BasePackage("graphviz")
        ],
        install_image = app -> begin
            # Install gprof2dot script
            COPY(app, Base.joinpath(@__DIR__, "gprof2dot.py"), "/opt/gprof2dot.py")
            # Install bash util functions script
            COPY(app, Base.joinpath(@__DIR__, "gprof.sh"), "/opt/gprof.sh")
            RUN(app, "cat /opt/gprof.sh >> $(ContainedEnv.home(app))/.bashrc")
        end
    )
end
export CodeProfiler