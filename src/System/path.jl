module Paths

abstract type AbstractPath end
segments(path::AbstractPath) = path.segments

# Utilitaries on AbstractPaths (works also for interportaltion)
Base.show(io::IO, x::AbstractPath) = Base.show(io, Base.string(x))

# Comparison Utilitaries
Base.:(==)(x::AbstractPath, y::AbstractPath) = (typeof(x)==typeof(y)) && (segments(x)==segments(y))
Base.:(==)(x::AbstractPath, y::String) = "$x" == y


macro __define_pathtype(PathType)
    return quote
        struct $PathType <: AbstractPath
            segments::Vector{String}
            # TODO: Raise Exception when split is unsuccessfull ?
            $PathType(path::AbstractString) = new(Base.split(path, __split_char($PathType)))
            $PathType(segments::Vector{String}) = new(copy(segments))
            $PathType(p::AbstractPath) = new(p.segments)
            # Parse all substrings as path and concatenate
            $PathType(segments::AbstractString...) = new(vcat(map(s -> Path(s).segments, collect(segments))...))
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

# Concatenation Utilitaries (TODO: More generic way ?)
# TODO: Specialize Base.joinpath ?
joinpath(x::AbstractString...) = pathtype()(x...)
joinpath(x::AbstractPath, y::AbstractString...) = typeof(x)(Base.vcat(segments(x), y...))
joinpath(x::AbstractPath, y::Vector{String}) = typeof(x)(Base.vcat(segments(x), y))
joinpath(x::AbstractPath, y::AbstractPath) = typeof(x)(Base.vcat(segments(x), segments(y)))

# Concatenation operator
Base.:(*)(x::AbstractPath, y::AbstractString) = joinpath(x, y)
Base.:(*)(x::AbstractPath, y::AbstractPath) = joinpath(x, y)

# Load path with correct type depending on path formatting
# TODO: optimize ?
function Path(x::AbstractString)::AbstractPath
    pp = PosixPath(x)
    wp = WindowsPath(x)
    return length(pp.segments) >= length(wp.segments) ? pp : wp
end


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

macro p_str(strargs)
    # Read String as PosixPath
    pathtype()(Path(strargs))
end

# Posix Path macro
macro pp_str(strargs)
    # Read String as PosixPath
    PosixPath(Path(strargs))
end

# Windows Path macro
macro wp_str(strargs)
    # Read String as PosixPath
    WindowsPath(Path(strargs))
end

export  AbstractPath, PosixPath, WindowsPath, Path,
        joinpath, pathtype, segments, @path, @p_str, @pp_str, @wp_str
end