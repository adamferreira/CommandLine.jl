using CommandLine

s = LocalGitBash()

function run2(s::Shell, cmd::Union{Base.Cmd, String})
    lock(s.run_mutex) do 
        write(instream(s), "$(cmd)")
    end
end

str = raw"""
function mafonction() {
    arg1=$1
}   echo $arg1
"""