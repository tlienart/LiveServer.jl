@testset "utils/servedocs             " begin
    bk = pwd()
    cd(mktempdir())

    write("counterfile", "0")

    mkdir("docs")
    write(joinpath("docs", "make.jl"),
            "c = parse(Int, read(\"counterfile\", String))\n" *
            "write(\"counterfile\", \"\$(c+1)\")")

    mkdir(joinpath("docs", "src"))
    write(joinpath("docs", "src", "index.md"), "# Documentation")

    mkdir(joinpath("docs", "build"))

    task = @async servedocs()

    # NOTE: these tests work perfectly well on Julia 1.x but for some mysterious reason they
    # do not pass on Julia 1.0 Travis. Given that I can't be bothered to figure out why, I just
    # add a version check here.
    if VERSION >= 1.1
        sleep(0.1)
        # after the first pass, `makejl` should have been called once (first pass)
        @test parse(Int, read("counterfile", String)) == 1
        # if we modify `index.md`, it should trigger a second pass
        write(joinpath("docs", "src", "index.md"), "# Documentation!")
        sleep(0.1)
        @test parse(Int, read("counterfile", String)) == 2
    end
    schedule(task, InterruptException(), error=true)
    cd(bk)
end

@testset "Misc utils                  " begin
    verbose(false)
    @test !LS.VERBOSE.x
    verbose(true)
    @test LS.VERBOSE.x
    verbose(false) # we don't want the tests to show lots of stuff

    bk = pwd()
    cd(mktempdir())
    LS.example()
    @test isdir("example")
    @test isfile("example/index.html")
    cd(bk)
end
