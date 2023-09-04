
# All test will be perfomed locally with a bash process

@testset "Test capture stdout" begin
    s = CLI.LocalGitBash()
    @test CLI.stringoutput(s, "echo 'Hello World'") == "Hello World"
    outputs = CLI.checkoutput(s, `"for((i=1;i<=3;i+=1)); do sleep 0; echo "Test"; done"`)
    @test outputs == ["Test", "Test", "Test"]
end

@testset "Test stdout handling" begin
    s = CLI.LocalGitBash(; handler = CLI.stringoutput)
    @test CLI.run(s, "echo 'Hello World'") == "Hello World"
    @test "echo 'Hello World'" |> s == "Hello World"
    #@test run"echo 'Hello World'"s == "Hello World"
end

@testset "Test env variables" begin
    s = CLI.LocalGitBash(; pwd = "~", env = Dict("Toto" => "Tata"))
    @test s["Toto"] == s[:Toto] == "Tata"
    # Test echoing the env variable itself
    @test CLI.stringoutput(s, raw"echo $Toto") == "Tata"
    # Setting values
    s["Toto"] = "Titi"
    @test s["Toto"] == s[:Toto] == "Titi"
    s[:Toto] = :Tutu
    @test s["Toto"] == s[:Toto] == "Tutu"
end

@testset "File and Dir manipulation" begin
    s = CLI.LocalGitBash()
    #workdir = @__DIR__
    # Transform the workdir into a posixpath (we are in a bash session) if it's not the case
    #workdir = stringoutput(s, "cygpath --unix $workdir")
    CLI.indir(s, "~") do s
        @test CLI.isdir(s, ".")
        # Create a non empty file
        CLI.nooutput(s, "echo 'Hello World' >> toto.txt")
        @test CLI.isfile(s, "~/toto.txt")
        @test CLI.stringoutput(s, "cat ~/toto.txt") == "Hello World"
        @test CLI.filesize(s, "~/toto.txt") == 12 # bytes
        
        CLI.rm(s, "~/toto.txt")
        @test !CLI.isfile(s, "~/toto.txt")
    end
end