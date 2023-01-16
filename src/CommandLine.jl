module CommandLine
"""
Instead of immediately running the command, backticks create a Cmd object to represent the command. 
You can use this object to connect the command to others via pipes, run it, and read or write to it.
When the command is run, Julia does not capture its output unless you specifically arrange for it to. 
Instead, the output of the command by default goes to stdout as it would using libc's system call.
The command is never run with a shell. 
Instead, Julia parses the command syntax directly, appropriately interpolating variables and splitting on words as the shell would, respecting shell quoting syntax. 
The command is run as julia's immediate child process, using fork and exec calls.


The following assumes a Posix environment as on Linux or MacOS. 
On Windows, many similar commands, such as echo and dir, are not external programs and instead are built into the shell cmd.exe itself. 
One option to run these commands is to invoke cmd.exe, for example cmd /C echo hello. 
Alternatively Julia can be run inside a Posix environment such as Cygwin.
"""

import Base.:(==)

#include("path.jl")
#export  AbstractPath, PosixPath, WindowsPath, segments, joinpath, @path, pathtype

include("Session/session.jl")
export  AbstractSession,
        BashSession,
        LocalBashSession,
        run, checkoutput, showoutput


        
DEFAULT_SESSION = nothing
macro run(cmd)
    showoutput(cmd, DEFAULT_SESSION)
end

showoutput(cmd::AbstractString) = showoutput(cmd, DEFAULT_SESSION)

export default_session, @run

function __init__()
    DEFAULT_SESSION = LocalBashSession()
end

# Precompile CommandLine package
__precompile__()
end