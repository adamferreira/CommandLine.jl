module ContainedEnv
import CommandLine as CLI
import CommandLine.Docker as Docker

struct Package
    name::String
    tag::String
end

Package(pname::String) = Package(pname, "base")

Base.hash(p::Package) = Base.hash(Base.hash(p.name), Base.hash(p.tag))
function parse_pkg(p::String)
    m = match(r"(?<name>[\w]+)#(?<tag>[\w]*)", p)
    return Package(m["name"], m["tag"])
end

mutable struct PackageManager
    installed::Set{Package}
    dependencies::Dict{Package, Set{Package}}
    PackageManager() = new(Set{Package}(), Dict{Package, Set{Package}}())
end

function add_pkg!(pm::PackageManager, p::Package; requires::Vector{Package} = [])
    pm.dependencies[p] = Set{Package}(requires)
end

function add_pkg!(pm::PackageManager; name::String, tag::String, requires::Vector{Package} = [])
    add_pkg!(pm, Package(name, tag), requires=requires)
end

function add_pkg!(pm::PackageManager; name::String, tag::String, requires::Vector{String} = [])
    add_pkg!(pm; name=name, tag=tag, requires=parse_pkg.(requires))
end

"""
    Environnement
- `app::String`: Name of the app to be deployed
- `user::String`: Username to use in the container
- `shell::Shell`: Shell on which docker commands will be launched
"""
mutable struct Environnement
    app::String
    user::String
    shell::CLI.Shell
end

end