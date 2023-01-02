
# All test will be perfomed locally with a bash process

@testset "Test bash" begin
    @test_nowarn CommandLine.local_bash_session()
end

test_session = CommandLine.local_bash_session()

@testset "Test capture stdout" begin
    outputs = Vector{String}()
    process = CommandLine.run(test_session, `"for((i=1;i<=3;i+=1)); do sleep 0; echo "Test"; done"`; 
        new_out = x::String -> push!(outputs, strip(x))
    )
    
    @test process.exitcode == 0
    @test outputs == ["Test", "Test", "Test", ""]

end

@testset "Test capture stderr" begin
    errors = Vector{String}()
    process = CommandLine.run(test_session, `unknown_command`; 
        new_err = x::String -> push!(errors, strip(x))
    )
    
    @show errors

end