using Test
using CommandLine

@testset "Test construction" begin
    pp = PosixPath(["A", "B"])
    wp = WindowsPath(["A", "B"])

    @test isa(pp, AbstractPath)
    @test isa(wp, AbstractPath)
    @test nodes(pp) == nodes(wp)
end

@testset "Test stringify" begin
    pp = PosixPath(["A", "B"])
    wp = WindowsPath(["A", "B"])

    @test Base.convert(String, pp) == "A/B"
    @test Base.convert(String, wp) == "A\\B"
    @test "$(pp)" == Base.convert(String, pp)
    @test "$(wp)" == Base.convert(String, wp)
end

@testset "Test join" begin
    pp = PosixPath(["A", "B"])
    wp = WindowsPath(["A", "B"])
    j1 = CommandLine.join(pp, ["C", "D"])
    j2 = CommandLine.join(wp, "C", "D")
    j3 = CommandLine.join(wp, pp)

    @test isa(j1, PosixPath)
    @test isa(j2, WindowsPath)
    @test isa(j3, WindowsPath)
    @test nodes(j1) == ["A", "B", "C", "D"]
    @test nodes(j2) == ["A", "B", "C", "D"]
    @test nodes(j3) == ["A", "B", "A", "B"]
end
