

function __check_path(flag::AbstractString, path, s::BashSession)
    out = CommandLine.stringoutput("if [[ $(flag) $(path) ]]; then echo \"true\"; else echo \"false\"; fi", s)
    return Base.parse(Bool, out)
end

joinpath(x, y...) = Base.join(vcat(x, [y...]), '/')

"""
    isdir(path, s::BashSession) -> Bool
The path `path` must define `string(path)`
"""
isdir(path, s::BashSession=default_session()) = __check_path("-d", path, s)
isfile(path, s::BashSession=default_session()) = __check_path("-f", path, s)
islink(path, s::BashSession=default_session()) = __check_path("-L", path, s)
isexe(path, s::BashSession=default_session()) = __check_path("-x", path, s)
abspath(path; s::BashSession=default_session()) = CommandLine.stringoutput("realpath $(path)", s)
pwd(s::BashSession=default_session()) = CommandLine.stringoutput("pwd", s)

function ls(path, args::AbstractString...; s::BashSession=default_session(), join::Bool=false)
    strargs = Base.join(vcat(args...), ' ')
    paths = CommandLine.checkoutput("ls $(strargs) $(path)", s)
    join && return [CommandLine.joinpath(path,p) for p in paths]
    return paths
end