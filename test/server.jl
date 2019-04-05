@testset "Miscellaneous               " begin

    # requested path --> a filesystem path
    bk = pwd()
    cd(dirname(dirname(pathof(LiveServer))))
    req = "foo"
    @test LS.get_fs_path(req) == ""
    req = "/test/dummies/index.html"
    @test LS.get_fs_path(req) == "./test/dummies/index.html"
    cd(bk)

    
end
