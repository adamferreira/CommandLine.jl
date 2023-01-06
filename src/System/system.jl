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


function ls(path::AbstractPath, session::AbstractSession)
    out = CommandLine.checkoutput(`ls $path`, session)
    return [
        join(path, pathtype(session)(line)) for line in split(out, '\n') if line != ""
    ]
end

# On local Session we use Julia.Sytem for efficiency reasons
# join=true to get full paths
function ls2(path::AbstractPath, session::LocalSession=LocalBashSession())
    return [ pathtype(session)(line) for line in Base.readdir("$path"; join = true) ]
end