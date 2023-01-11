"""
@enum PathType begin
    posix_path = 1
    windows_path
end
"""

abstract type AbstractPath end
segments(path::AbstractPath) = path.segments

# Utilitaries on AbstractPaths
Base.show(io::IO, x::AbstractPath) = Base.show(io, Base.string(x))
# Concatenation Utilitaries (TODO: More generic way ?)
join(x::AbstractPath, y::AbstractString...) = typeof(x)(Base.vcat(segments(x), y...))
join(x::AbstractPath, y::Vector{String}) = typeof(x)(Base.vcat(segments(x), y)) #TODO: Vector of abstract strings ?
join(x::AbstractPath, y::AbstractPath) = typeof(x)(Base.vcat(segments(x), segments(y)))

# Comparison Utilitaries
Base.:(==)(x::AbstractPath, y::AbstractPath) = (typeof(x)==typeof(y)) && (segments(x)==segments(y))
Base.:(==)(x::AbstractPath, y::String) = "$x" == y


macro __define_pathtype(PathType)
    return quote
        struct $PathType <: AbstractPath
            segments::Vector{String}
            $PathType(segments::Vector{String}) = new(segments)
            $PathType(segments::AbstractString...) = new([segments...])
            # TODO: Raise Exception when split is unsuccessfull ?
            $PathType(path::AbstractString) = new(Base.split(path, __split_char($PathType)))
        end
    end |> esc
end

@__define_pathtype PosixPath
@__define_pathtype WindowsPath

__split_char(::Type{PosixPath}) = "/"
__split_char(::Type{WindowsPath}) = "\\"
Base.convert(::Type{String}, x::AbstractPath) = Base.join(segments(x), __split_char(typeof(x)))
Base.string(x::AbstractPath) = Base.join(segments(x), __split_char(typeof(x)))
Base.convert(t::Type{PosixPath}, x::AbstractPath) = t(segments(x))
Base.convert(t::Type{WindowsPath}, x::AbstractPath) = t(segments(x))


"""
    Get the path type (AbstractPath) of the current operating system
"""
function pathtype()
    if Sys.iswindows()
        return WindowsPath
    end
    if Sys.isapple() || Sys.isunix()
        return PosixPath
    end
end


"""
    Macro to create the appropriate AbstractPath from the current operating system
"""
macro path(args...)
    pathtype()(args...)
end

joinpath(x::AbstractString...) = pathtype()(x...)