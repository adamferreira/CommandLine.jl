

function __check_path(flag::AbstractString, path, s::AbstractBashSession)
    out = CommandLine.stringoutput(s, "if [[ $(flag) $(path) ]]; then echo \"true\"; else echo \"false\"; fi")
    return Base.parse(Bool, out)
end

joinpath(x, y...) = Base.join(vcat(x, [y...]), '/')

"""
    isdir(s::AbstractBashSession, path) -> Bool
The path `path` must define `string(path)`
"""
isdir(s::AbstractBashSession, path) = __check_path("-d", path, s)
isfile(s::AbstractBashSession, path) = __check_path("-f", path, s)
islink(s::AbstractBashSession, path) = __check_path("-L", path, s)
isexe(s::AbstractBashSession, path) = __check_path("-x", path, s)
abspath(s::AbstractBashSession, path) = CommandLine.stringoutput(s, "realpath $(path)")
parent(s::AbstractBashSession, path) = CommandLine.stringoutput(s, "dirname $(path)")
pwd(s::AbstractBashSession) = CommandLine.stringoutput(s, "pwd")
cd(s::AbstractBashSession, path) = CommandLine.stringoutput(s, "cd $(path)")
cp(s::AbstractBashSession, src, dest) = CommandLine.stringoutput(s, "cd $(scr) $(dest)")


function env(session::AbstractBashSession)
    return CommandLine.checkoutput(session, "env")
end

function ls(session::AbstractBashSession, path, args::AbstractString...; join::Bool=false)
    strargs = Base.join(vcat(args...), ' ')
    paths = CommandLine.checkoutput(session, "ls $(strargs) $(path)")
    join && return CommandLine.joinpath.(path, paths)
    return paths
end

function rm(session::AbstractBashSession, path, args::AbstractString...)
    strargs = Base.join(vcat(args...), ' ')
    CommandLine.stringoutput(session, "rm $(strargs) $(path)")
end

function mkdir(session::AbstractBashSession, path, args::AbstractString...)
    strargs = Base.join(vcat(args...), ' ')
    CommandLine.stringoutput(session, "mkdir $(strargs) $(path)")
end

function chmod(session::AbstractBashSession, path, args::AbstractString...)
    strargs = Base.join(vcat(args...), ' ')
    CommandLine.stringoutput(session, "chmod $(strargs) $(path)")
end