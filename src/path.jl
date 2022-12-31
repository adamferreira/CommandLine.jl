@enum PathType begin
    posix_path = 1
    windows_path
end

abstract type AbstractPath end
nodes(path::AbstractPath) = path.nodes

# Utilitaries on AbstractPaths
Base.show(io::IO, x::AbstractPath) = Base.print(io, "$(Base.convert(String, x))")
# Concatenation Utilitaries (TODO: More generic way ?)
join(x::AbstractPath, y::String...) = typeof(x)(Base.vcat(nodes(x), y...))
join(x::AbstractPath, y::Vector{String}) = typeof(x)(Base.vcat(nodes(x), y))
join(x::AbstractPath, y::AbstractPath) = typeof(x)(Base.vcat(nodes(x), nodes(y)))
# Comparison Utilitaries


macro __define_pathtype(PathType)
    return quote
        struct $PathType <: AbstractPath
            nodes::Vector{String}
            $PathType(nodes::Vector{String}) = new(nodes)
        end
    end |> esc
end

@__define_pathtype PosixPath
@__define_pathtype WindowsPath

function Base.convert(::Type{String}, x::PosixPath)
    return Base.join(nodes(x), '/')
end

function Base.convert(::Type{String}, x::WindowsPath)
    return Base.join(nodes(x), "\\")
end