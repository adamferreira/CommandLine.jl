"""
@enum PathType begin
    posix_path = 1
    windows_path
end
"""

abstract type AbstractPath end
nodes(path::AbstractPath) = path.nodes

# Utilitaries on AbstractPaths
Base.show(io::IO, x::AbstractPath) = Base.print(io, "$(Base.convert(String, x))")
# Concatenation Utilitaries (TODO: More generic way ?)
join(x::AbstractPath, y::AbstractString...) = typeof(x)(Base.vcat(nodes(x), y...))
join(x::AbstractPath, y::Vector{String}) = typeof(x)(Base.vcat(nodes(x), y)) #TODO: Vector of abstract strings ?
join(x::AbstractPath, y::AbstractPath) = typeof(x)(Base.vcat(nodes(x), nodes(y)))

# Comparison Utilitaries
Base.:(==)(x::AbstractPath, y::AbstractPath) = (typeof(x)==typeof(y)) && (nodes(x)==nodes(y))
Base.:(==)(x::AbstractPath, y::String) = "$x" == y


macro __define_pathtype(PathType)
    return quote
        struct $PathType <: AbstractPath
            nodes::Vector{String}
            $PathType(nodes::Vector{String}) = new(nodes)
            $PathType(nodes::AbstractString...) = new([nodes...])
            # TODO: Raise Exception when split is unsuccessfull ?
            $PathType(path::AbstractString) = new(Base.split(path, __split_char($PathType)))
        end
    end |> esc
end

@__define_pathtype PosixPath
@__define_pathtype WindowsPath

__split_char(::Type{PosixPath}) = "/"
__split_char(::Type{WindowsPath}) = "\\"
Base.convert(::Type{String}, x::AbstractPath) = Base.join(nodes(x), __split_char(typeof(x)))
Base.convert(t::Type{PosixPath}, x::AbstractPath) = t(nodes(x))
Base.convert(t::Type{WindowsPath}, x::AbstractPath) = t(nodes(x))