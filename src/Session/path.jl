"""
    An `AbstractPath` that represents a bind between an `AbstractPath` and an `AbstractSession`
    Particulary usefull to call a FileSystem function on remote paths as they will store their remote session.
"""
struct BindedPath{PT <: AbstractPath, ST <: AbstractSession} <: AbstractPath
    path::PT
    session::ST
    #BindedPath(p::PT, s::ST) = BindedPath{PT,ST}(p,s)
end

"""
    As we ultimatly work with string-like paths, we only need to specialize `Base.string`
"""
Base.string(path::BindedPath{PT,ST}) where {PT,ST} = Base.string(path.path)
CommandLine.segments(path::BindedPath{PT,ST}) where {PT,ST} = CommandLine.segments(path.path)

bindpath(p::AbstractPath, s::AbstractSession) = BindedPath{typeof(p), Nothing}(p, s)