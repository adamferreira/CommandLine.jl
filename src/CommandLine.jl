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
export LocalSession, run


#session = BashSession(; template_config = StoringConfig(), type = LocalSession)
#@time p, in, out, err = command(session, `ls .`)()
#println(out)
#@time p, in, out, err = command(session, `"for((i=1;i<=10;i+=1)); do sleep 1; echo "Toto"; done"`)() #command(session, `echo "Step !" '&&' sleep 5 '&&' echo "Step 2 !"`)()
#@show out


v = ["1"]
session = local_bash_session()
@show v
run(session, `"for((i=1;i<=10;i+=1)); do sleep 1; echo "Toto"; done"`, new_out = x -> println(strip(x)))
@show v

# Precompile CommandLine package
__precompile__()
end