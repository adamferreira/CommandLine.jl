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


function ls(path::AbstractPath, session::AbstractSession = LocalBashSession())
    paths = Vector{pathtype(session)}()
    function treat_string_blob(x::String)
        if x == "" return; end
        for line in split(x, '\n')
            if line != ""
                push!(paths, join(path, pathtype(session)(line)))
            end
        end
    end

    process = CommandLine.run(`ls $path`, session; new_out = x::String -> treat_string_blob(x))
    return paths
    """
    out = CommandLine.checkoutput(session, `ls $path`)
    return [
        join(path, pathtype(session)(line)) for line in split(out, '\n') if line != ""
    ]
    """
end

# On local Session we use Julia.Sytem for efficiency reasons
# join=true to get full paths
#ls(path::AbstractPath, session::LocalSession) = readdir("$path") #TODO: make them path