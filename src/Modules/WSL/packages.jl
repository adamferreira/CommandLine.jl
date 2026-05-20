function AptGet()::Package
    return Package(
        "AptGet"; requires = [],
        on_install = wsli -> begin
            CMD(wsli, "$(sudo(wsli)) apt-get upgrade -y")
            CMD(wsli, "$(sudo(wsli)) apt-get update -y")
        end
    )
end
export AptGet

function AptBundle(bname::String, bundle::String...)::Package
    packages = join([bundle...], " ")
    return Package(
        bname; requires = [],
        on_install = wsli -> begin
            CMD(wsli, "$(sudo(wsli)) apt-get upgrade -y")
            CMD(wsli, "$(sudo(wsli)) apt-get update -y")
            CMD(wsli, "$(sudo(wsli)) apt-get install -y $(packages)")
        end,
        on_update = wsli -> begin
            CMD(wsli, "$(sudo(wsli)) apt-get upgrade -y")
            CMD(wsli, "$(sudo(wsli)) apt-get update -y")
            CMD(wsli, "$(sudo(wsli)) apt-get install -y --only-upgrade $(packages)")
        end,
        on_delete = wsli -> begin
            CMD(wsli, "$(sudo(wsli)) apt-get upgrade -y")
            CMD(wsli, "$(sudo(wsli)) apt-get update -y")
            CMD(wsli, "$(sudo(wsli)) apt-get purge --auto-remove $(packages)")
        end
    )
end
export AptBundle

function AptPackage(pname::String)::Package
    return Package(
        pname; requires = [AptGet()],
        on_install = wsli -> begin
            CMD(wsli, "$(sudo(wsli)) apt-get install -y $(pname)")
        end,
        on_update = wsli -> begin
            CMD(wsli, "$(sudo(wsli)) apt-get install -y --only-upgrade $(pname)")
        end,
        on_delete = wsli -> begin
            CMD(wsli, "$(sudo(wsli)) apt-get purge --auto-remove $(pname)")
        end
    )
end
export AptPackage


CmakeSuite() = AptBundle("CmakeSuite", "make", "cmake", "cmake-curses-gui")
export CmakeSuite

function GccAMD64(version = v"15.2.0"; additonnal_deps::Vector{Package} = Vector{Package}())::Package
    pkg_install_workspace = (wsli, p) -> Paths.joinpath(pkg_datadir(pkmg(wsli), p).instance, "install")
    pkg_build_workspace = (wsli, p) -> Paths.joinpath(pkg_datadir(pkmg(wsli), p).instance, "build")
    tarball_name = (wsli, p) -> "$(pretty_name(p)).tar.gz"
    final_tarball = (wsli, p) -> PathBridge(Paths.joinpath(WSLJLHOSTHOME, tarball_name(wsli, p)) => Paths.joinpath(pkg_datadir(pkmg(wsli), p).instance, tarball_name(wsli, p)))

    build_pkg = Package(
        "gcc_build", version; requires = [ 
            # Basic packages need to compile gcc
            AptPackage("wget"), AptPackage("bzip2"), 
            AptPackage("flex"), AptPackage("unzip"),
            # Obviously we need a compiler !
            AptPackage("make"), AptPackage("automake"), # for aclocal-1.16
            AptPackage("cmake"), AptPackage("gcc"), AptPackage("g++"),
            additonnal_deps...
        ],
        # Only build if we can't find a compiled tarball locally
        should_build = wsli -> !isfile(final_tarball(wsli, current_pkg(pkmg(wsli))).host |> string),
        should_install = wsli -> !isfile(final_tarball(wsli, current_pkg(pkmg(wsli))).host |> string),
        # Build tarball        
        on_build = wsli -> begin
            thisp = current_pkg(pkmg(wsli))
            CMD(wsli, "$(sudo(wsli)) mkdir -p $(pkg_build_workspace(wsli, thisp))")
            CMD(wsli, "$(sudo(wsli)) mkdir -p $(pkg_install_workspace(wsli, thisp))")
            CMD(wsli, "cd $(pkg_build_workspace(wsli, thisp))")
            CMD(wsli, "wget https://github.com/gcc-mirror/gcc/archive/refs/tags/releases/gcc-$(version).zip")
            CMD(wsli, "unzip gcc-$(version).zip")
            CMD(wsli, "cd gcc-releases-gcc-$(version)")
            CMD(wsli, "./contrib/download_prerequisites")
            CMD(wsli, "./configure --prefix=$(pkg_install_workspace(wsli,thisp)) --disable-multilib --enable-languages=c,c++")
            CMD(wsli, "make -j16")
            CMD(wsli, "make install")
            # Make tarball
            CMD(wsli, "tar -cvf $(final_tarball(wsli, thisp).instance) -C $(pkg_install_workspace(wsli, thisp)) .")
        end,
        # Move tarball to host (`on_install` is run AFTER `on_build`)
        on_install = wsli -> begin
            copy_to_host(wsli, final_tarball(wsli, current_pkg(pkmg(wsli))))
        end
    )

    return Package(
        "gcc", version; requires = [],
        # Always run install script for outer package
        should_build = wsli -> !isfile(final_tarball(wsli, build_pkg).host |> string),
        on_build = wsli -> begin
            # Create a buffer WSL instance to compile the Package
            # This will avoid install all the package dependencies into the the main target instance
            # This also avoid having the build data into the main instance
            info(wsli, "Creating external instance `pretty_name(build_pkg)` to build `$(name(build_pkg)):$(version)`")
            tmp_wsli = WSLInstance(pretty_name(build_pkg), user(wsli), Paths.joinpath(workspace(wsli), uid(build_pkg)))
            add_pkg!(tmp_wsli, build_pkg)
            try
                import_from_scratch!(
                    tmp_wsli;
                    local_tarball = tarball_location(wsli),
                    regenerate_if_exists = true
                )
                unregister!(tmp_wsli)
            catch e
                unregister!(tmp_wsli)
                throw(e)                    
            end
        end,
        # At this point, the tarball SHOULD exist on host
        on_install = wsli -> begin
            # Move local tarball to instance
            run_on_instance(wsli, "$(sudo(wsli)) mkdir -p $(pkg_install_workspace(wsli, build_pkg))")
            copy_to_instance(wsli, final_tarball(wsli, build_pkg))
            # Extract tarball to desired folder
            CMD(wsli, "$(sudo(wsli)) tar -xvf $(final_tarball(wsli, build_pkg).instance) -C $(pkg_install_workspace(wsli, build_pkg))")
            # Remove tarball after extraction
            CMD(wsli, "$(sudo(wsli)) rm $(final_tarball(wsli, build_pkg).instance)")
            # Set defaults
            CMD(wsli, "$(sudo(wsli)) update-alternatives --install /usr/bin/g++ g++ $(pkg_install_workspace(wsli, build_pkg))/bin/g++ 100")
            CMD(wsli, "$(sudo(wsli)) update-alternatives --install /usr/bin/gcc gcc $(pkg_install_workspace(wsli, build_pkg))/bin/gcc 100")
        end
        # TODO: Add CC and CXX to bashrc
    )
end
export GccAMD64

function CPythonAMD64(
    version = v"3.13.11";
    additonnal_deps::Vector{Package} = Vector{Package}(),
    pip_packages::Vector{String} = Vector{String}()
)::Package
    tarball_name = (wsli, p) -> "$(pretty_name(p)).tar.gz"
    final_tarball = (wsli, p) -> PathBridge(Paths.joinpath(WSLJLHOSTHOME, tarball_name(wsli, p)) => Paths.joinpath(pkg_datadir(pkmg(wsli), p).instance, tarball_name(wsli, p)))

    build_pkg = Package(
        "cpython", version; requires = [ 
            map(p -> AptPackage(p), [
                "wget", "curl",
                "unzip", "bzip2",
                "pkg-config",
                "build-essential",
                "gdb",
                "lcov",
                "pkg-config",
                "libbz2-dev",
                "libffi-dev",
                "libgdbm-dev",
                "libgdbm-compat-dev",
                "liblzma-dev",
                "libncurses5-dev",
                "libreadline6-dev",
                "libsqlite3-dev",
                "libssl-dev",
                "lzma",
                "lzma-dev",
                "tk-dev",
                "uuid-dev",
                "zlib1g-dev",
                "libzstd-dev",
                "inetutils-inetd"
            ])...,
            additonnal_deps...
        ],
        # Only build if we can't find a compiled tarball locally
        should_build = wsli -> !isfile(final_tarball(wsli, current_pkg(pkmg(wsli))).host |> string),
        should_install = wsli -> !isfile(final_tarball(wsli, current_pkg(pkmg(wsli))).host |> string),
        # Build tarball        
        on_build = wsli -> begin
            thisp = current_pkg(pkmg(wsli))
            # TODO: automate this part
            CMD(wsli, "$(sudo(wsli)) mkdir -p $(pkg_build_workspace(wsli, thisp))")
            CMD(wsli, "$(sudo(wsli)) mkdir -p $(pkg_install_workspace(wsli, thisp))")
            CMD(wsli, "cd $(pkg_build_workspace(wsli, thisp))")
            CMD(wsli, "wget https://github.com/python/cpython/archive/refs/tags/v$(version).zip")
            CMD(wsli, "unzip v$(version).zip")
            CMD(wsli, "cd cpython-$(version)")
            CMD(wsli, "./configure --prefix=$(pkg_install_workspace(wsli, thisp))")
            CMD(wsli, "make -j16")
            CMD(wsli, "make install")
            # Make tarball
            CMD(wsli, "tar -cvf $(final_tarball(wsli, thisp).instance) -C $(pkg_install_workspace(wsli, thisp)) .")
        end,
        # Move tarball to host (`on_install` is run AFTER `on_build`)
        on_install = wsli -> begin
            copy_to_host(wsli, final_tarball(wsli, current_pkg(pkmg(wsli))))
        end
    )

    return Package(
        "python", version; requires = [additonnal_deps...],
        # Always run install script for outer package
        should_build = wsli -> !isfile(final_tarball(wsli, build_pkg).host |> string),
        on_build = wsli -> begin
            # Create a buffer WSL instance to compile the Package
            # This will avoid install all the package dependencies into the the main target instance
            # This also avoid having the build data into the main instance
            info(wsli, "Creating external instance `pretty_name(build_pkg)` to build `$(name(build_pkg)):$(version)`")
            tmp_wsli = WSLInstance(pretty_name(build_pkg), user(wsli), Paths.joinpath(workspace(wsli), uid(build_pkg)))
            add_pkg!(tmp_wsli, build_pkg)
            try
                import_from_scratch!(
                    tmp_wsli;
                    local_tarball = tarball_location(wsli),
                    regenerate_if_exists = true
                )
                unregister!(tmp_wsli)
            catch e
                unregister!(tmp_wsli)
                throw(e)                    
            end
        end,
        # At this point, the tarball SHOULD exist on host
        on_install = wsli -> begin
            # Move local tarball to instance
            run_on_instance(wsli, "$(sudo(wsli)) mkdir -p $(pkg_install_workspace(wsli, build_pkg))")
            copy_to_instance(wsli, final_tarball(wsli, build_pkg))
            # Extract tarball to desired folder
            CMD(wsli, "$(sudo(wsli)) tar -xvf $(final_tarball(wsli, build_pkg).instance) -C $(pkg_install_workspace(wsli, build_pkg))")
            # Remove tarball after extraction
            CMD(wsli, "$(sudo(wsli)) rm $(final_tarball(wsli, build_pkg).instance)")
            # Set defaults
            CMD(wsli, "$(sudo(wsli)) update-alternatives --install /usr/bin/python python $(pkg_install_workspace(wsli, build_pkg))/bin/python3 100")
            CMD(wsli, "$(sudo(wsli)) update-alternatives --install /usr/bin/python3 python3 $(pkg_install_workspace(wsli, build_pkg))/bin/python3 100")
            if (length(pip_packages)) > 0
                for pip_p in pip_packages
                    CMD(wsli, "python -m pip install $(pip_p)")
                end
            end
        end
    )
end
export CPythonAMD64

function JuliaAMD64(version = v"1.12.0"; additonnal_deps::Vector{Package} = Vector{Package}())
    # https://github.com/JuliaLang/juliaup/releases/download/v1.19.9/juliaup-1.19.9-x86_64-unknown-linux-musl-portable.tar.gz
    return Package(
        "julia", version; requires = [],
        should_install = wsli -> begin
            return true
        end,
        on_install = wsli -> begin
            @show WSLJLHOSTHOME
        end
    )
end
export JuliaAMD64

function SSHKeys(local_pub, local_priv, local_known_hosts = nothing)::Package
    uuid = Base.hash(Base.hash("$local_pub"), Base.hash("$local_priv"))
    return Package(
        "SSHKeys", string(uuid); requires = [],
        on_install = wsli -> begin
            for host_file in [local_pub, local_priv, local_known_hosts]
                @assert isfile(host_file |> string)
                if !isnothing(host_file)
                    filename = CLI.basename(hostshell(wsli), Paths.PosixPath(host_file))
                    copy_to_instance(wsli, PathBridge(host_file => Paths.joinpath(home(wsli), ".ssh", filename)))
                    CMD(wsli, "$(sudo(wsli)) chmod 600 $(Paths.joinpath(home(wsli), ".ssh", filename))")
                end
            end
        end
    )
end
export SSHKeys

function DotNet()::Package
    return Package(
        "dotnet", "latest" ; requires = [AptPackage("curl"), AptPackage("unzip")],
        on_install = wsli -> begin
            CMD(wsli, "curl -sSL https://dot.net/v1/dotnet-install.sh | bash")
        end,
        on_bashrc = wsli -> begin
            ADDENV(wsli, "PATH", Paths.joinpath(home(wsli), ".dotnet"))
        end
    )
end
export DotNet

function wslu(browser::Symbol = :firefox)::Package
    # See: https://wslu.wedotstud.io/wslu/install.html
    # https://itsfoss.com/add-apt-repository-command-not-found/
    return Package(
        "wslu"; requires = [AptPackage("software-properties-common")],
        on_install = wsli -> begin
            CMD(wsli, "$(sudo(wsli)) add-apt-repository ppa:wslutilities/wslu -y")
            CMD(wsli, "$(sudo(wsli)) apt-get install wslu -y")
        end,
        on_bashrc = wsli -> begin
            SETENV(wsli, "BROWSER", "/mnt/c/Program\\ Files/Mozilla\\ Firefox/firefox.exe")
        end
    )
end

export wslu