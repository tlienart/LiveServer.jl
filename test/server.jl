@testset "Get File                    " begin

    bk = pwd()
    cd(splitdir(splitdir(pathof(LiveServer))[1])[1])

    req = "foo"
    @test LS.get_fs_path(req) == ""

    req = "/test/dummies/index.html"
    @test LS.get_fs_path(req) == "./test/dummies/index.html"

    cd(bk)
end
