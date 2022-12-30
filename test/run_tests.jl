using CommandLine

c = `powershell -Command dir` # `cmd /c `
p = run(c)