

function __check_path(flag::AbstractString, path, s::BashSession)
    out = CommandLine.stringoutput(s, "if [[ $(flag) $(path) ]]; then echo \"true\"; else echo \"false\"; fi")
    return Base.parse(Bool, out)
end

joinpath(x, y...) = Base.join(vcat(x, [y...]), '/')

"""
    isdir(s::BashSession, path) -> Bool
The path `path` must define `string(path)`
"""
isdir(s::BashSession, path) = __check_path("-d", path, s)
isfile(s::BashSession, path) = __check_path("-f", path, s)
islink(s::BashSession, path) = __check_path("-L", path, s)
isexe(s::BashSession, path) = __check_path("-x", path, s)
abspath(s::BashSession, path) = CommandLine.stringoutput(s, "realpath $(path)")
parent(s::BashSession, path) = CommandLine.stringoutput(s, "dirname $(path)")
pwd(s::BashSession) = CommandLine.stringoutput(s, "pwd")
cd(s::BashSession, path) = CommandLine.stringoutput(s, "cd $(path)")
cp(s::BashSession, src, dest) = CommandLine.stringoutput(s, "cd $(scr) $(dest)")


function env(session::BashSession)
    return CommandLine.checkoutput(session, "env")
end

function ls(session::BashSession, path, args::AbstractString...; join::Bool=false)
    strargs = Base.join(vcat(args...), ' ')
    paths = CommandLine.checkoutput(session, "ls $(strargs) $(path)")
    join && return CommandLine.joinpath.(path, paths)
    return paths
end

function rm(session::BashSession, path, args::AbstractString...)
    strargs = Base.join(vcat(args...), ' ')
    CommandLine.stringoutput(session, "rm $(strargs) $(path)")
end

function mkdir(session::BashSession, path, args::AbstractString...)
    strargs = Base.join(vcat(args...), ' ')
    CommandLine.stringoutput(session, "mkdir $(strargs) $(path)")
end

function chmod(session::BashSession, path, args::AbstractString...)
    strargs = Base.join(vcat(args...), ' ')
    CommandLine.stringoutput(session, "chmod $(strargs) $(path)")
end