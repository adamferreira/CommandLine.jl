
# All test will be perfomed locally with a bash process

#@testset "Test bash" begin
#    @test_nowarn LocalGitBash()
#end

@testset "Test capture stdout" begin
    s = LocalGitBash()
    outputs = checkoutput(s, `"for((i=1;i<=3;i+=1)); do sleep 0; echo "Test"; done"`)
    @test outputs == ["Test", "Test", "Test"]
end