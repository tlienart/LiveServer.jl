# create files in a temporary dir that we can modify
const tmpdir = mktempdir()
const file1 = joinpath(tmpdir, "file1")
const file2 = joinpath(tmpdir, "file2")
write(file1, ".")
write(file2, ".")

@testset "Watcher/WatchedFile struct  " begin
    wf1 = LS.WatchedFile(file1)
    wf2 = LS.WatchedFile(file2)

    # Basic struct
    @test wf1.path == file1
    @test wf2.path == file2
    @test wf1.mtime == mtime(file1)
    @test wf2.mtime == mtime(file2)

    # Apply change and check if it's detecte
    t1 = time()
    sleep(FS_WAIT)
    write(file1, "hello")
    sleep(FS_WAIT)
    @test LS.has_changed(wf1) == 1
    @test LS.has_changed(wf2) == 0

    # Set state as unchanged
    LS.set_unchanged!(wf1)
    @test LS.has_changed(wf1) == 0
    @test wf1.mtime > t1
end

@testset "Watcher/SimpleWatcher struct" begin
    sw  = LS.SimpleWatcher()

    isa(sw, LS.FileWatcher)

    sw1 = LS.SimpleWatcher(identity, sleeptime=0.0)

    # Base constructor check
    @test sw.callback === nothing
    @test sw.task === nothing
    @test sw.sleeptime == 0.1
    @test isempty(sw.watchedfiles)
    @test eltype(sw.watchedfiles) == LS.WatchedFile

    @test sw1.sleeptime == 0.05 # via the clamping
    @test sw1.callback(2) == 2 # identity function
    @test sw1.callback("blah") == "blah"
    @test isempty(sw1.watchedfiles)
    @test sw1.task === nothing
end

@testset "Watcher/watch  file routines" begin
    sw = LS.SimpleWatcher(identity)

    LS.watch_file!(sw, file1)
    LS.watch_file!(sw, file2)

    @test sw.watchedfiles[1].path == file1
    @test sw.watchedfiles[2].path == file2

    # is_watched
    @test LS.is_watched(sw, file1)
    @test LS.is_watched(sw, file2)

    # is_running?
    @test !LS.is_running(sw)

    LS.start(sw)
    sleep(0.001)

    @test LS.is_running(sw)
    @test LS.stop(sw)
    @test !LS.is_running(sw)

    #
    # modify callback to something that will eventually throw an error
    #
    LS.set_callback!(sw, log)
    @test sw.callback(exp(1.0)) ≈ 1.0

    LS.start(sw)
    sleep(0.001)

    # causing a modification will generate an error because the callback
    # function will fail on a string
    cray = Crayon(foreground=:cyan, bold=true)
    println(cray, "\n⚠ Deliberately causing an error to be displayed and handled...\n")
    write(file1, "modif")
    sleep(0.25) # needs to be sufficient to give time for propagation.
    @test sw.status == :interrupted

    #
    # deleting files
    #

    file3 = joinpath(tmpdir, "file3")
    write(file3, "hello")

    sw = LS.SimpleWatcher(identity)

    LS.watch_file!(sw, file1)
    LS.watch_file!(sw, file2)
    LS.watch_file!(sw, file3)

    @test length(sw.watchedfiles) == 3

    LS.start(sw)

    rm(file3)
    sleep(0.25) # needs to be sufficient to give time for propagation.

    # file3 was deleted
    @test length(sw.watchedfiles) == 2
    @test sw.watchedfiles[1].path == file1
    @test sw.watchedfiles[2].path == file2
end
