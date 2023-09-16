
# ------------------------------------------------------------------
# Define all system call for Bash-like shells (sh, bash, ...)
# ------------------------------------------------------------------


function __check_path(flag::AbstractString, path, s)
    out = CommandLine.stringoutput(s, "if [[ $(flag) $(path) ]]; then echo \"true\"; else echo \"false\"; fi")
    return Base.parse(Bool, out)
end

posix_joinpath(x, y...) = Base.join(vcat(x, [y...]), '/')

"""
    isdir(s::BashShell, path) -> Bool
The path `path` must define `string(path)`
"""
isdir(s::BashShell, path) = __check_path("-d", path, s)
isfile(s::BashShell, path) = __check_path("-f", path, s)
islink(s::BashShell, path) = __check_path("-L", path, s)
isexe(s::BashShell, path) = __check_path("-x", path, s)
abspath(s::BashShell, path) = CommandLine.stringoutput(s, "realpath $(path)")
parent(s::BashShell, path) = CommandLine.stringoutput(s, "dirname $(path)")
basename(s::BashShell, path) = CommandLine.stringoutput(s, "basename $(path)")
pwd(s::BashShell) = CommandLine.stringoutput(s, "pwd")
cd(s::BashShell, path) = CommandLine.nooutput(s, "cd $(path)")
cp(s::BashShell, src, dest) = CommandLine.nooutput(s, "cp $(src) $(dest)")
filesize(s::BashShell, path)::Int = Base.parse(Int, CommandLine.stringoutput(s, "stat -c%s $path"))

function env(s::BashShell)
    return CommandLine.checkoutput(s, "env")
end

# -u (unix) because of type `BashShell`
function cygpath(s::BashShell, path, args::AbstractString...)
    strargs = Base.join(vcat(args...), ' ')
    return CommandLine.stringoutput(s, ("cygpath $(strargs) \"$(path)\""))
end

cygpath(s::BashShell, path) = CommandLine.cygpath(s, path, "-u", args...)

function ls(s::BashShell, path, args::AbstractString...; join::Bool=false)
    strargs = Base.join(vcat(args...), ' ')
    paths = CommandLine.checkoutput(s, "ls $(strargs) $(path)")
    join && return posix_joinpath.(path, paths)
    return paths
end

function rm(s::BashShell, path, args::AbstractString...)
    strargs = Base.join(vcat(args...), ' ')
    CommandLine.nooutput(s, "rm $(strargs) $(path)")
end

function mkdir(s::BashShell, path, args::AbstractString...)
    strargs = Base.join(vcat(args...), ' ')
    CommandLine.nooutput(s, "mkdir $(strargs) $(path)")
end

function chmod(s::BashShell, path, args::AbstractString...)
    strargs = Base.join(vcat(args...), ' ')
    CommandLine.nooutput(s, "chmod $(strargs) $(path)")
end