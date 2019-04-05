@testset "Misc utils                  " begin
    verbose(false)
    @test !LS.VERBOSE.x
    verbose(true)
    @test LS.VERBOSE.x

    bk = pwd()
    cd(mktempdir())
    LS.example()
    @test isdir("example")
    @test isfile("example/index.html")
    cd(bk)
end
