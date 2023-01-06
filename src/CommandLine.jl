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

include("path.jl")
export  AbstractPath, PosixPath, WindowsPath,
        nodes, join

include("Session/session.jl")
export  AbstractSession, LocalSession, LocalBashSession,
        run, checkoutput, showoutput

include("System/system.jl")
export @path, pathtype, ls

function f1()
    s = LocalBashSession()
    out1 = checkoutput(`"for((i=1;i<=100;i+=1)); do sleep 0.1; echo "Toto1"; done"`, s)
    out2 = checkoutput(`"for((i=1;i<=100;i+=1)); do sleep 0.1; echo "Toto2"; done"`, s)
    return out1, out2
end

function f2()
    s = LocalBashSession()
    t1 = @async checkoutput(`"for((i=1;i<=100;i+=1)); do sleep 0.1; echo "Toto1"; done"`, s)
    t2 = @async checkoutput(`"for((i=1;i<=100;i+=1)); do sleep 0.1; echo "Toto2"; done"`, s)
    return fetch(t1), fetch(t2)
end

function f3()
    s = LocalBashSession()
    out1 = showoutput(`"for((i=1;i<=10;i+=1)); do sleep 1; echo "Toto1"; done"`, s)
    out2 = showoutput(`"for((i=1;i<=10;i+=1)); do sleep 1; echo "Toto2"; done"`, s)
    return out1, out2
end

function f4()
    s = LocalBashSession()
    t1 = @async showoutput(`"for((i=1;i<=10;i+=1)); do sleep 1; echo "Toto1"; done"`, s)
    t2 = @async showoutput(`"for((i=1;i<=10;i+=1)); do sleep 3; echo "Toto2"; done"`, s)
    return fetch(t1), fetch(t2)
end

@show ls2(@path "..")
println(@path ".\\.git")

# Precompile CommandLine package
__precompile__()
end