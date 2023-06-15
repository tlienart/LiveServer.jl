@testset "utils/servedocs-callback    " begin
    bk = pwd()
    cd(mktempdir())

    mkdir("docs")
    mkdir(joinpath("docs", "src"))
    write(joinpath("docs", "src", "index.md"), "Index file")
    write(joinpath("docs", "src", "index2.md"), "Random file")

    thispath = pwd()
    makejl = joinpath("docs", "make.jl")

    # this is a slight of hand to increment a counter when `make.jl` is executed so that
    # we can check it's executed the appropriate number of times
    write("tempfile", "0")
    write(makejl,
          """
          c = parse(Int, read(\"tempfile\", String)); write(\"tempfile\", \"\$(c+1)\")
          """
    )
    readmake() = parse(Int, read("tempfile", String))

    include(abspath(makejl))
    @test readmake() == 1

    def = (nothing, String[], String[], String[], String[], "docs", "build")

    # callback function
    dw = LS.SimpleWatcher()
    LS.servedocs_callback!(dw, makejl, makejl, def...)

    @test length(dw.watchedfiles) == 3
    @test dw.watchedfiles[1].path == joinpath("docs", "make.jl")
    @test dw.watchedfiles[2].path == joinpath("docs", "src", "index.md")
    @test dw.watchedfiles[3].path == joinpath("docs", "src", "index2.md")

    @test readmake() == 2

    # let's now remove `index2.md`
    rm(joinpath("docs", "src", "index2.md"))
    LS.servedocs_callback!(dw, makejl, makejl, def...)

    # the file has been removed
    @test length(dw.watchedfiles) == 2
    @test readmake() == 3

    # let's check there's an appropriate trigger for index
    LS.servedocs_callback!(dw, joinpath("docs", "src", "index.md"), makejl, def...)
    @test length(dw.watchedfiles) == 2
    @test readmake() == 4

    cd(bk)
end

@testset "utils/servedocs-scan-docs   " begin
    bk = pwd()
    cd(mktempdir())
    dw = LS.SimpleWatcher()

    # error if there's no docs/ folder
    cray = Crayon(foreground=:cyan, bold=true)
    println(cray, "\n⚠ Deliberately causing an error to be displayed and handled...\n")
    @test_throws ErrorException LS.scan_docs!(dw, "docs", "", "", String[], String[])

    empty!(dw.watchedfiles)

    mkdir("docs")
    mkdir(joinpath("docs", "src"))
    write(joinpath("docs", "src", "index.md"), "Index file")
    write(joinpath("docs", "src", "index2.md"), "Random file")
    write(joinpath("docs", "make.jl"), "1+1")

    mkdir("extradir")
    write(joinpath("extradir", "extra.md"), "Extra source file")

    mkdir("extradir2")
    write(joinpath("extradir2", "extra2.md"), "Extra source file 2")

    mkdir(joinpath("docs", "lit"))
    write(joinpath("docs", "lit", "index.jl"), "1+1")

    LS.scan_docs!(dw, "docs", "docs/make.jl", joinpath("docs", "lit"), [abspath("extradir")], [abspath("extradir2", "extra2.md")])

    @test length(dw.watchedfiles) == 5 # index.jl, index2.md, make.jl, extra.md, extra2.md
    @test endswith(dw.watchedfiles[1].path, "make.jl")
    @test endswith(dw.watchedfiles[2].path, "index2.md")
    @test endswith(dw.watchedfiles[3].path, "extra.md")
    @test endswith(dw.watchedfiles[4].path, "extra2.md")
    @test endswith(dw.watchedfiles[5].path, "index.jl")

    cd(bk)
end

@testset "utils/servedocs-callback with foldername    " begin
    bk = pwd()
    cd(mktempdir())

    mkdir("site")
    mkdir(joinpath("site", "src"))
    write(joinpath("site", "src", "index.md"), "Index file")
    write(joinpath("site", "src", "index2.md"), "Random file")

    makejl = joinpath("site", "make.jl")

    # this is a slight of hand to increment a counter when `make.jl` is executed so that
    # we can check it's executed the appropriate number of times
    write("tempfile", "0")
    write(makejl, "c = parse(Int, read(\"tempfile\", String)); write(\"tempfile\", \"\$(c+1)\")")

    readmake() = parse(Int, read("tempfile", String))

    include(abspath(makejl))
    @test readmake() == 1

    # callback function
    dw = LS.SimpleWatcher()

    LS.servedocs_callback!(dw, makejl, makejl, "", String[], String[], String[], String[], "site", "build")

    @test length(dw.watchedfiles) == 3
    @test dw.watchedfiles[1].path == joinpath("site", "make.jl")
    @test dw.watchedfiles[2].path == joinpath("site", "src", "index.md")
    @test dw.watchedfiles[3].path == joinpath("site", "src", "index2.md")

    @test readmake() == 2

    # let's now remove `index2.md`
    rm(joinpath("site", "src", "index2.md"))
    LS.servedocs_callback!(dw, makejl, makejl, "", String[], String[], String[], String[], "site", "build")

    # the file has been removed
    @test length(dw.watchedfiles) == 2
    @test readmake() == 3

    # let's check there's an appropriate trigger for index
    LS.servedocs_callback!(dw, joinpath("site", "src", "index.md"), makejl, "", String[], String[], String[], String[], "site", "build")
    @test length(dw.watchedfiles) == 2
    @test readmake() == 4

    cd(bk)
end

@testset "utils/servedocs-scan-docs with foldername   " begin
    bk = pwd()
    cd(mktempdir())
    dw = LS.SimpleWatcher()

    # error if there's no docs/ folder
    cray = Crayon(foreground=:cyan, bold=true)
    println(cray, "\n⚠ Deliberately causing an error to be displayed and handled...\n")
    @test_throws ErrorException LS.scan_docs!(dw, "site", "site", "", String[], String[])

    empty!(dw.watchedfiles)

    mkdir("site")
    mkdir(joinpath("site", "src"))
    write(joinpath("site", "src", "index.md"), "Index file")
    write(joinpath("site", "src", "index2.md"), "Random file")
    write(joinpath("site", "make.jl"), "1+1")

    mkdir(joinpath("site", "lit"))
    write(joinpath("site", "lit", "index.jl"), "1+1")

    LS.scan_docs!(dw, "site", "site/make.jl", joinpath("site", "lit"), String[], String[])

    @test length(dw.watchedfiles) == 3 # index.jl, index2.md, make.jl
    @test endswith(dw.watchedfiles[1].path, "make.jl")
    @test endswith(dw.watchedfiles[2].path, "index2.md")
    @test endswith(dw.watchedfiles[3].path, "index.jl")

    cd(bk)
end

@testset "Misc utils                  " begin
    LS.set_verbose(false)
    @test !LS.VERBOSE.x
    LS.set_verbose(true)
    @test LS.VERBOSE.x
    LS.set_verbose(false) # we don't want the tests to show lots of stuff

    bk = pwd()
    cd(mktempdir())
    LS.example()
    @test isdir("example")
    @test isfile("example/index.html")
    cd(bk)
end


@testset "utils/servedocs_literate    " begin
    bk = pwd()
    tdir = mktempdir()
    cd(tdir)
    LiveServer.servedocs_literate_example("test")
    @test isdir("test")
    @test isfile(joinpath("test", "docs", "literate", "man",  "pg1.jl"))
    @test isfile(joinpath("test", "docs", "src", "index.md"))
    @test isfile(joinpath("test", "src", "test.jl"))
    cd(bk)
    rm(tdir, recursive=true)
end
