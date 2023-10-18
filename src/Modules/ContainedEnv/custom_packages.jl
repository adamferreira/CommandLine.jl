
function JuliaLinux(version::String = "1.8.0-rc1")::Package
    # SOURCE: https://github.com/docker-library/julia/blob/3eb14343427c06437c5eda730ce8df1aeff5eb36/1.8-rc/bullseye/Dockerfile
    # For example 1.8.0-rdc -> NAME = "-rdc"
    m = match(r"(?<MAJOR>\d)\.(?<MINOR>\d)\.(?<PATCH>\d)(?<NAME>\-[\w]*)*", version)
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

function GitHubRepo(
    repourl::String, user::String, usermail::String;
    on::Symbol = :image,
    dest::String = ""
)::Package
    on_host = nothing
    on_image = nothing
    on_container = nothing

    if on == :host
        on_host = app -> begin
            # Clone git repo locally
            
        end
    end

    if on == :image
        on_image = app -> begin
            RUN(
                app,
                "git clone $(repourl)",
                "git config --local user.name $(user)",
                "git config --local user.email $(usermail)"
            )
        end
    end

    return Package(
        "GitHubRepo", "$(repourl)";
        install_host = on == :host ? on_host : nothing,
        install_image = on == :image ? on_image : nothing,
        install_container = on == :container ? on_container : nothing,
        requires = [
            BasePackage("git")
        ]
    )

end