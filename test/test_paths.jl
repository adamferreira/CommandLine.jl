@testset "Test construction" begin
    pp = PosixPath(["A", "B"])
    wp = WindowsPath(["A", "B"])

    @test isa(pp, AbstractPath)
    @test isa(wp, AbstractPath)
    @test nodes(pp) == nodes(wp)
    @test PosixPath(["A", "B"]) == PosixPath("A", "B")
    @test PosixPath("A/B/C/D") == PosixPath("A", "B", "C", "D")
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

@testset "Test Equals" begin
    @test PosixPath(["A", "B"]) != WindowsPath(["A", "B"])
    @test PosixPath(["A", "B"]) == PosixPath(["A", "B"])
    @test PosixPath(["A", "B"]) != PosixPath(["A", "C"])
    @test PosixPath(["A", "B", "C", "D"]) == "A/B/C/D"
end

@testset "Test Convert" begin
    @test Base.convert(PosixPath, WindowsPath("A", "B")) == "A/B"
    @test Base.convert(WindowsPath, WindowsPath("A", "B")) != "A/B"
    @test Base.convert(WindowsPath, PosixPath("A", "B")) == WindowsPath("A", "B")
end