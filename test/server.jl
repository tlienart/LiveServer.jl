@testset "Get File                    " begin

    bk = pwd()
    cd(splitdir(splitdir(pathof(LiveServer))[1])[1])

    req = "foo"
    @test LS.get_file(req) === nothing

    req = "/test/dummies/index.html"
    @test LS.get_file(req) == "./test/dummies/index.html"

    cd(bk)
end
