@testset "Test construction" begin
    pp = PosixPath(["A", "B"])
    wp = WindowsPath(["A", "B"])

    @test isa(pp, AbstractPath)
    @test isa(wp, AbstractPath)
    @test segments(pp) == segments(wp)
    @test PosixPath(["A", "B"]) == PosixPath("A", "B")
    @test PosixPath("A/B/C/D") == PosixPath("A", "B", "C", "D")
    @test PosixPath("A", "B", "C", "D") == PosixPath("A", "B", "C", "D")
    @test PosixPath("A/B", "C/D") == PosixPath("A", "B", "C", "D")
    @test PosixPath("/A/B", "C/D") == PosixPath("/A", "B", "C", "D")
end

@testset "Test stringify" begin
    pp = PosixPath(["A", "B"])
    wp = WindowsPath(["A", "B"])

    @test Base.convert(String, pp) == "A/B"
    @test Base.convert(String, wp) == raw"A\B"
    @test "$(pp)" == Base.convert(String, pp)
    @test "$(wp)" == Base.convert(String, wp)
end

@testset "Test join" begin
    pp = PosixPath(["A", "B"])
    wp = WindowsPath(["A", "B"])
    j1 = Paths.joinpath(pp, ["C", "D"])
    j2 = Paths.joinpath(wp, "C", "D")
    j3 = Paths.joinpath(wp, pp)

    @test segments(j1) == ["A", "B", "C", "D"]
    @test segments(j2) == ["A", "B", "C", "D"]
    @test segments(j3) == ["A", "B", "A", "B"]
    @test segments(Paths.joinpath("A", "B", "C", "D")) == ["A", "B", "C", "D"]
    @test segments(j1 * "E" * "F") == ["A", "B", "C", "D", "E", "F"]
    @test segments(j1 * PosixPath("E", "F")) == ["A", "B", "C", "D", "E", "F"]
end

@testset "Test Equals" begin
    @test PosixPath(["A", "B"]) != WindowsPath(["A", "B"])
    @test PosixPath(["A", "B"]) == PosixPath(["A", "B"])
    @test PosixPath(["A", "B"]) != PosixPath(["A", "C"])
    @test PosixPath(["A", "B", "C", "D"]) == "A/B/C/D"
    @test PosixPath(["A", "B/B", "C", "D/E"]) == "A/B/B/C/D/E"
end

@testset "Test Convert" begin
    @test Base.convert(PosixPath, WindowsPath("A", "B")) == "A/B"
    @test Base.convert(WindowsPath, WindowsPath("A", "B")) != "A/B"
    @test Base.convert(WindowsPath, PosixPath("A", "B")) == WindowsPath("A", "B")
end

@testset "Test path deduction" begin
    if Sys.iswindows()
        @test pathtype() == WindowsPath
    else
        @test pathtype() == PosixPath
    end
end

@testset "Test path macro" begin
    @test segments(@path "A" "B" "C") == ["A", "B", "C"]
    @test pp"A/B/C" == PosixPath("A", "B", "C")
    @test wp"A/B/C" == WindowsPath("A", "B", "C")
    @test pp"A\B\C" == PosixPath("A", "B", "C")
    @test wp"A\B\C" == WindowsPath(raw"A\B\C") == WindowsPath("A\\B\\C") == WindowsPath("A", "B", "C")

    @test segments(p"A/B/C") == ["A", "B", "C"]
    @test segments(p"A\B\C") == ["A", "B", "C"]
end