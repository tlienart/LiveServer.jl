@testset "utils/servedocs-callback    " begin
    bk = pwd()
    cd(mktempdir())

    mkdir("docs")
    mkdir(joinpath("docs", "src"))
    write(joinpath("docs", "src", "index.md"), "Index file")
    write(joinpath("docs", "src", "index2.md"), "Random file")

    thispath = pwd()
    makejl = joinpath(thispath, "make.jl")

    # this is a slight of hand to increment a counter when `make.jl` is executed so that
    # we can check it's executed the appropriate number of times
    write("tempfile", "0")
    write("make.jl", "c = parse(Int, read(\"tempfile\", String)); write(\"tempfile\", \"\$(c+1)\")")

    readmake() = parse(Int, read("tempfile", String))

    include(makejl)
    @test readmake() == 1

    # callback function
    vwf = Vector{LS.WatchedFile}()

    LS.servedocs_callback(makejl, vwf, makejl)

    @test length(vwf) == 2
    @test vwf[1].path == joinpath("docs", "src", "index.md")
    @test vwf[2].path == joinpath("docs", "src", "index2.md")
    @test readmake() == 2

    # let's now remove `index2.md`
    rm(joinpath("docs", "src", "index2.md"))
    LS.servedocs_callback(makejl, vwf, makejl)

    # the file has been removed
    @test length(vwf) == 1
    @test readmake() == 3

    # let's check there's an appropriate trigger for index
    LS.servedocs_callback(joinpath("docs", "src", "index.md"), vwf, makejl)
    @test length(vwf) == 1
    @test readmake() == 4

    # but a random should not trigger
    LS.servedocs_callback("whatever", vwf, makejl)
    @test readmake() == 4

    cd(bk)
end

@testset "utils/servedocs-scan-docs   " begin
    bk = pwd()
    cd(mktempdir())

    mkdir("docs")
    mkdir(joinpath("docs", "src"))
    write(joinpath("docs", "src", "index.md"), "Index file")
    write(joinpath("docs", "src", "index2.md"), "Random file")
    write(joinpath("docs", "make.jl"), "1+1")

    dw = LS.SimpleWatcher()
    makejl = LS.scan_docs!(dw)

    @test makejl == joinpath("docs", "make.jl")
    @test length(dw.watchedfiles) == 3 # index, index2, make
    @test endswith(dw.watchedfiles[1].path, "make.jl")
    @test endswith(dw.watchedfiles[2].path, "index.md")
    @test endswith(dw.watchedfiles[3].path, "index2.md")

    cd(bk)
end

@testset "Misc utils                  " begin
    LS.setverbose(false)
    @test !LS.VERBOSE.x
    LS.setverbose(true)
    @test LS.VERBOSE.x
    LS.setverbose(false) # we don't want the tests to show lots of stuff

    bk = pwd()
    cd(mktempdir())
    LS.example()
    @test isdir("example")
    @test isfile("example/index.html")
    cd(bk)
end
