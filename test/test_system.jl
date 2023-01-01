@testset "Test path deduction" begin
    if Sys.iswindows()
        @test pathtype() == WindowsPath
    else
        @test pathtype() == PosixPath
    end
end

@testset "Test path macro" begin
    @test nodes(@path "A" "B" "C") == ["A", "B", "C"]
end