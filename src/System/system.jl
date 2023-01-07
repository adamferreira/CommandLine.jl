# Assumes include("path.jl"), Sesssion/*

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

# Do not type path here as we would like to accept String and Path like object (FilePaths.jl: https://github.com/rofinn/FilePathsBase.jl)
function ls(path, session::AbstractSession)
    out = CommandLine.checkoutput(`ls $path`, session)
    return [
        join(path, pathtype(session)(line)) for line in split(out, '\n') if line != ""
    ]
end