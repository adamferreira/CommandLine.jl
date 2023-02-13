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
        RemoteSSHSession,
        close,
        run, checkoutput, stringoutput, showoutput

include("System/bash_commands.jl")
export  isdir, isfile, islink, isexe, abspath, parent, pwd,
        cd, env, cp, ls, rm, mkdir, chmod

include("System/transfer.jl")
export  default_ssh_keys, scp1, transfer_files

include("System/git.jl")
export  git_status, changes, tracked_files

include("System/file.jl")
export  watch_files


# Global default session is a local bash session
# `bash` must exist on the local machine !
DEFAULT_SESSION = nothing
default_session() = DEFAULT_SESSION

# Forward Bash calls with default sesstion
for fct in Symbol[
    :checkoutput,
    :showoutput,
    :stringoutput,
    :isdir,
    :isfile,
    :islink,
    :isexe,
    :abspath,
    :parent,
    :cd,
    :ls,
    :rm,
    :mkdir,
    :chmod,
]
@eval $(fct)(cmd, args...; kwargs...) = $(fct)(default_session(), cmd, args...; kwargs...)
end
# TODO: :env


# Utilitaries macros and exports
macro run(cmd)
    showoutput(default_session(), cmd)
end

export @run, default_session

# Open local bash session when loading the package
function __init__()
    global DEFAULT_SESSION = LocalBashSession()
end

# Precompile CommandLine package
__precompile__()
end