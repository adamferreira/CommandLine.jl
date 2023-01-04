
# All test will be perfomed locally with a bash process

@testset "Test bash" begin
    @test_nowarn CommandLine.LocalBashSession()
end

test_session = CommandLine.LocalBashSession()

@testset "Test capture stdout" begin
    outputs = Vector{String}()
    process = CommandLine.run(`"for((i=1;i<=3;i+=1)); do sleep 0; echo "Test"; done"`, test_session; 
        new_out = x::String -> push!(outputs, strip(x))
    )
    
    @test process.exitcode == 0
    @test outputs == ["Test", "Test", "Test", ""]

end

@testset "Test capture stderr" begin
    errors = Vector{String}()
    process = CommandLine.run(`unknown_command`, test_session; 
        new_err = x::String -> push!(errors, strip(x))
    )
    
    @test length(errors) >= 1
end

@testset "Test checkoutput" begin
    @test_throws Base.IOError checkoutput(`ls fakepath`, test_session)
end