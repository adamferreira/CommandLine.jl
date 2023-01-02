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

posix_cmd(cmd::Base.Cmd) = cmd
windows_cmd(cmd::Base.Cmd) = `cmd /C $cmd`
powershell_cmd(cmd::Base.Cmd) = `powershell -Command $cmd`

include("path.jl")
export AbstractPath, PosixPath, WindowsPath, nodes, join

include("system.jl")
export @path, pathtype

include("Session/session.jl")
export LocalSession, local_bash_session, run

test_session = CommandLine.local_bash_session()


outputs = Vector{String}()
function treat_string_blob(x::String)
    if x == "" return; end
    for line in split(x, '\n')
        if line != ""
            push!(outputs, line)
        end
    end
end
@time process = CommandLine.run(test_session, `ls`;
    new_out = x::String -> treat_string_blob(x)
)
@show outputs

# Precompile CommandLine package
__precompile__()
end