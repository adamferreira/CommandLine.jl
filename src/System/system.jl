# Assumes include("path.jl"), Sesssion/*

# Do not type path here as we would like to accept String and Path like object (FilePaths.jl: https://github.com/rofinn/FilePathsBase.jl)
function ls(path, session::AbstractSession)
    out = CommandLine.checkoutput(`ls $path`, session)
    return [
        join(path, line) for line in split(out, '\n') if line != ""
    ]
end