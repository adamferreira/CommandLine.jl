using CommandLine

s = LocalGitBash()

CommandLine.indir(s, "Projects") do s 
    ls(s, ".")
end