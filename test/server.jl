@testset "Server/Paths                " begin
    # requested path --> a filesystem path
    bk = pwd()
    cd(joinpath(@__DIR__, ".."))
    req = "tmp"
    @test LS.get_fs_path(req) == ""
    req = "/test/dummies/index.html"
    @test LS.get_fs_path(req) == "test/dummies/index.html"
    req = "/test/dummies/r%C3%A9sum%C3%A9/"
    @test LS.get_fs_path(req) == "test/dummies/résumé/index.html"
    req = "/test/dummies/"
    @test LS.get_fs_path(req) == "test/dummies/index.html"
    req = "/test/dummies/?query=string"
    @test LS.get_fs_path(req) == "test/dummies/index.html"
    cd(bk)

    @test LS.append_slash("/a/b") == "/a/b/"
    @test LS.append_slash("/a/b?c=d") == "/a/b/?c=d"
    @test LS.append_slash("/a/b/?c=d") == "/a/b/?c=d"
end

#=
NOTE: if extending these tests, please be careful. As they involve @async tasks which,
themselves, spawn async tasks, if your tests fail for some reason you will HAVE to kill
the current Julia session and restart one otherwise the tasks that haven't been killed
due to the tests not being finished properly will keep running and may clash with new
tasks that you will try to start.
=#
@testset "Server/Step-by-step testing " begin
    #
    # STEP 0: cd to dummies
    #
    bk = pwd()
    cd(dirname(dirname(pathof(LiveServer))))
    cd(joinpath("test", "dummies"))
    port = 8123

    isdir("css") && rm("css", recursive=true)
    isfile("tmp.html") && rm("tmp.html")
    isdir("404") && rm("404", recursive=true)

    write("tmp.html", "blah")
    mkdir("css")
    write("css/foo.css", "body { color: pink; }")

    #
    # STEP 1: launching the listener
    #
    # assert 8000 ≤ port ≦ 9000
    @test_throws ArgumentError serve(port=7000)
    @test_throws ArgumentError serve(port=10000)

    # define filewatcher outside so that can follow it
    fw = LS.SimpleWatcher(LS.file_changed_callback)
    task = @async serve(fw; port=port)
    sleep(0.1) # give it time to get started

    # there should be a callback associated with fw now
    @test fw.status == :runnable
    # the filewatcher should be running
    @test LS.is_running(fw)
    # it also should be empty thus far
    @test isempty(fw.watchedfiles)

    #
    # STEP 2: triggering a request
    #
    response = HTTP.get("http://localhost:$port/")
    @test response.status == 200
    # the browser script should be appended
    @test String(response.body) == replace(read("index.html", String),
                            "</body>"=>"$(LS.BROWSER_RELOAD_SCRIPT)</body>")
    hdict = Dict(response.headers)
    @test occursin("text/html", hdict["Content-Type"])
    # if one asks for something incorrect, a 404 should be returned
    response = HTTP.get("http://localhost:$port/no.html"; status_exception=false)
    @test response.status == 404
    @test occursin("404: file not found.", String(response.body))
    # test custom 404.html page
    mkdir("404"); write("404/index.html", "custom 404")
    response = HTTP.get("http://localhost:$port/no.html"; status_exception=false)
    @test response.status == 404
    @test occursin("custom 404", String(response.body))
    # if one asks for something without a </body>, it should just be appended
    response = HTTP.get("http://localhost:$port/tmp.html")
    @test response.status == 200
    @test String(response.body) == read("tmp.html", String) * LS.BROWSER_RELOAD_SCRIPT
    response = HTTP.get("http://localhost:$port/css/foo.css")
    @test String(response.body) == read("css/foo.css", String)
    @test response.status == 200

    # we asked earlier for index.html therefore that file should be followed
    @test fw.watchedfiles[1].path == "index.html"
    # also 404
    @test fw.watchedfiles[2].path == "404/index.html"
    # also tmp
    @test fw.watchedfiles[3].path == "tmp.html"
    # and the css
    @test fw.watchedfiles[4].path == "css/foo.css"

    # if we modify the file, it should trigger the callback function which should open
    # and then subsequently close a websocket. We check this happens properly by adding
    # our own sentinel websocket
    function makews()
        req = HTTP.Request()
        return HTTP.WebSockets.WebSocket(HTTP.Connection(IOBuffer()), req, req.response; client=false)
    end
    sentinel = makews()
    LS.WS_VIEWERS["tmp.html"] = [sentinel]

    @test sentinel.io.io.writable
    write("tmp.html", "something new")
    sleep(0.1)
    # the sentinel websocket should be closed
    @test !sentinel.io.io.writable
    # the websockets should have been flushed
    @test isempty(LS.WS_VIEWERS["tmp.html"])

    # let's do this again with an infra file which will ping all websockets
    sentinel1 = makews()
    sentinel2 = makews()
    push!(LS.WS_VIEWERS["tmp.html"], sentinel1)
    LS.WS_VIEWERS["css/foo.css"] = [sentinel2]
    write("css/foo.css", "body { color:blue; }")
    sleep(0.1)
    # all sentinel websockets should be closed
    @test !sentinel1.io.io.writable
    @test !sentinel2.io.io.writable

    # if we remove the files, it shall stop following it
    rm("tmp.html")
    rm("css", recursive=true)
    rm("404", recursive=true)
    sleep(0.5)
    # only index.html is still watched
    @test length(fw.watchedfiles) == 1

    #
    # SHUTTING DOWN
    #
    # this should have interrupted the server, so it should be possible
    # to restart one on the same port (otherwise this will throw an error, already in use)
    schedule(task, InterruptException(), error=true)
    sleep(1.5) # give it time to get done
    @test istaskdone(task)
    @test begin
        server = Sockets.listen(port)
        sleep(0.1)
        close(server)
        true
    end == true

    # Check that WS_FILES is properly destroyed
    isempty(LS.WS_VIEWERS)

    cd(bk)
end

@testset "Server/ws_tracker testing   " begin
    bk = pwd()
    cd(mktempdir())
    write("test_file.html", "Hello!")

    server = Sockets.listen(Sockets.localhost, 8001)
    io = Sockets.connect(Sockets.localhost, 8001)
    key = "k5zQsAMXfFlvmWIE/YCiEg=="
    s = HTTP.Stream(HTTP.Request("GET", "http://localhost:8562/test_file.html",
    ["Connection" => "upgrade", "Upgrade" => "websocket", "Sec-WebSocket-Key" => key,
    "Sec-WebSocket-Version" => "13"]), HTTP.Connection(io))

    fs_path = LS.get_fs_path(s.message.target)
    @test fs_path == "test_file.html"

    tsk = @async LS.HTTP.WebSockets.upgrade(LS.ws_tracker, s)
    sleep(1.0)

    # the websocket should have been added to the list
    @test LS.WS_VIEWERS[fs_path] isa Vector{HTTP.WebSockets.WebSocket}
    @test length(LS.WS_VIEWERS[fs_path]) == 1

    # simulate a "good" closure (an event caused a write on the websocket and then closes it)
    ws = LS.WS_VIEWERS[fs_path][1]
    close(ws)
    sleep(1.0)
    @test istaskdone(tsk)
    @test !LS.WS_INTERRUPT[]

    io = Sockets.connect(Sockets.localhost, 8001)
    key = "k5zQsAMXfFlvmWIE/YCiEg=="
    s = HTTP.Stream(HTTP.Request("GET", "http://localhost:8562/test_file.html",
    ["Connection" => "upgrade", "Upgrade" => "websocket", "Sec-WebSocket-Key" => key,
    "Sec-WebSocket-Version" => "13"]), HTTP.Connection(io))

    tsk = @async LS.HTTP.WebSockets.upgrade(LS.ws_tracker, s)
    sleep(1.0)

    # simulate a "bad" closure
    schedule(tsk, InterruptException(), error=true)
    sleep(5.1) # wait until websockets force closes the socket
    @test istaskdone(tsk)
    @test LS.WS_INTERRUPT[]

    @test length(LS.WS_VIEWERS[fs_path]) == 2

    # cleanup
    close(server)
    empty!(LS.WS_VIEWERS)

    cd(bk)
end
