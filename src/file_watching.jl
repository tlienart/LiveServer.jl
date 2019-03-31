"A watched file; construct with its path as single argument"
mutable struct WatchedFile
    path::String
    mtime::Float64
    WatchedFile(path::String) = new(path, mtime(path))
end

"Check if a `WatchedFile` has changed"
has_changed(wf::WatchedFile) = mtime(wf.path) > wf.mtime

"Set the current state of a `WatchedFile` as unchanged"
set_unchanged!(wf::WatchedFile) = wf.mtime = mtime(wf.path)

"""
    SimpleWatcher(;sleeptime::Float64=0.1)

A simple file watcher. Has two channels that may be used once watching was
started with `start()`:

- `newfile_channel`: pass paths (String) to files that should be watched as well
- `filechange_channel` listen on this channel to get paths (String) of files that changed

The `sleeptime` is the time waited between to runs of the loop looking for
changed files. Both channels have length 1 (i.e. no queue); this simplifies implementation and
since the operations triggered by the messages are short (esp. shorter than
the usual frequency of messages) do not greatly impair performance.

You can stop the watcher (i.e. his two tasks) by closing the `newfile_channel`,
or use the commodity function `stop()` doing exactly this.
"""
struct SimpleWatcher
    newfile_channel::Channel{String}
    filechange_channel::Channel{String}
    filelist::Vector{WatchedFile}
    sleeptime::Float64

    function SimpleWatcher(;sleeptime::Float64=0.1)
        new(Channel{String}(1), Channel{String}(1), Vector{WatchedFile}(), sleeptime)
    end
end

"""
    is_file_watched(w::SimpleWatcher, path::String)

Checks whether a file is already being watched by `w`.
"""
is_file_watched(w::SimpleWatcher, path::String) = path ∈ [wf.path for wf ∈ w.filelist]

"[INTERNAL] Wait on `newfile_channel`, add file to watched files `filelist`"
function wait_for_files(w::SimpleWatcher)
    while true
        try wait(w.newfile_channel) catch _ break end # stop if channel closed
        msg = take!(w.newfile_channel)
        isfile(msg) && !is_file_watched(w, msg) && push!(w.filelist, WatchedFile(msg))
    end
    println("ℹ [SimpleWatcher]: \"wait_for_files\" task ending")
    return nothing
end

"[INTERNAL] File-watcher loop, putting messages to `filechange_channel` upon changes"
function watch_files(w::SimpleWatcher)
    while true
        # check if newfile_channel still open, otherwise terminate task
        # (which will also close filechange_channel)
        !isopen(w.newfile_channel) && break

        # check for changes on files
        foreach(w.filelist) do wf
            if has_changed(wf)
                set_unchanged!(wf)
                put!(w.filechange_channel, wf.path)
            end
        end

        sleep(w.sleeptime)
    end
    println("ℹ [SimpleWatcher]: \"watch_files\" task ending")
    return nothing
end

"""
    start(w::SimpleWatcher)

Start the file watcher. Spawns two coroutines to which the handles are
returned.
"""
function start(w::SimpleWatcher)
    # start task waiting for new files to be watched, bind life of channel to it
    # --> message -1 will terminate task and close this channel
    wff_task = @async wait_for_files(w)
    bind(w.newfile_channel, wff_task)

    # start task watching files, bind life of channel to it
    wf_task = @async watch_files(w)
    bind(w.filechange_channel, wf_task)

    return (wff_task, wf_task)
end

"""
    stop(w::SimpleWatcher)

Stop the watcher (i.e. its two async tasks).
"""
stop(w::SimpleWatcher) = close(w.newfile_channel)
