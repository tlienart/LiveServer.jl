@testset "Server/Paths                " begin
    # requested path --> a filesystem path
    bk = pwd()
    cd(dirname(dirname(pathof(LiveServer))))
    req = "foo"
    @test LS.get_fs_path(req) == ""
    req = "/test/dummies/index.html"
    @test LS.get_fs_path(req) == "./test/dummies/index.html"
    cd(bk)
end

@testset "Server/Step-by-step testing " begin
    #
    # STEP 0: cd to dummies
    #
    bk = pwd()
    cd(dirname(dirname(pathof(LiveServer))))
    cd(joinpath("test", "dummies"))
    port = 8123

    #
    # STEP 1: launching the listener
    #
    # assert 8000 ≤ port ≦ 9000
    @test_throws ArgumentError serve(port=7000)
    @test_throws ArgumentError serve(port=10000)

    # define filewatcher outside so that can follow it
    fw = LS.SimpleWatcher()
    task = @async serve(fw; port=port)
    sleep(0.1) # give it time to get started

    # there should be a callback associated with fw now
    @test fw.callback !== nothing
    @test fw.status == :runnable
    # the filewatcher should be running
    @test LS.isrunning(fw)
    # it also should be empty thus far
    @test isempty(fw.watchedfiles)

    #
    # SHUTTING DOWN
    #
    # this should have interrupted the server, so it should be possible
    # to restart one on the same port (otherwise this will throw an error, already in use)
    schedule(task, InterruptException(), error=true)
    sleep(0.25) # give it time to get done
    @test istaskdone(task)
    @test begin
        server = Sockets.listen(port)
        sleep(0.1)
        close(server)
        true
    end == true

    # end, cd back to where we were
    cd(bk)
end
