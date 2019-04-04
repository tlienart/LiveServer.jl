"A watched file; built with its path as single argument"
mutable struct WatchedFile{T<:AbstractString}
    path::T
    mtime::Float64
    WatchedFile(path) = new{typeof(path)}(path, mtime(path))
end

"Check if a `WatchedFile` has changed"
has_changed(wf::WatchedFile) = mtime(wf.path) > wf.mtime

"Set the current state of a `WatchedFile` as unchanged"
set_unchanged!(wf::WatchedFile) = wf.mtime = mtime(wf.path)

"""
    SimpleWatcher([callback];sleeptime::Float64=0.1)

A simple file watcher. You can specify a callback function, receiving the
path of each file that has changed as a string, at construction or later
by the API function described below. The `sleeptime` is the time waited
between to runs of the loop looking for changed files.

# API functions
TBD, where `w` is a `SimpleWatcher`. Main API functions (commonly used):

- `start(w)`
- `stop(w)`
- `set_callback(w, fcn::Function)`
- `watch_file(w, path::String)`

Further API functions (probably never used in a normal use case):

- `isrunning(w)`
- `is_file_watched(w, path::String)`
"""
mutable struct SimpleWatcher
    callback::Union{Nothing,Function}
    task::Union{Nothing,Task}
    sleeptime::Float64
    filelist::Vector{WatchedFile}
    SimpleWatcher(callback::Union{Nothing,Function}=nothing; sleeptime::Float64=0.1) =
        new(callback,nothing,max(0.05,sleeptime),Vector{WatchedFile}())
end

"""
    _file_watcher(w::SimpleWatcher)

[INTERNAL] Helper function that's spawned as an asynchronous task which
checks for changed files. Terminates normally upon a `InterruptException`,
and with a warning for all other exceptions.
"""
function _file_watcher(w::SimpleWatcher)
    try
        while true
            # only check files if there's a callback to call upon changes
            (w.callback != nothing) && foreach(w.filelist) do wf
                if has_changed(wf)
                    set_unchanged!(wf)
                    w.callback(wf.path)
                end
            end
            sleep(w.sleeptime)
        end
    catch EXC
        if !isa(EXC, InterruptException) # if interruption, normal termination
            @warn "Exception in file-watching task; please stop the server (Ctrl-C): " EXC
        end
    end
end

"""
    _waitfor_task_shutdown(w::SimpleWatcher)

[INTERNAL] Helper function ensuring that the `_file_watcher` task has ended
before continuing.
"""
function _waitfor_task_shutdown(w::SimpleWatcher)
    while !istaskdone(w.task)
        sleep(0.05)
    end
end

"""
    set_callback(w::SimpleWatcher, fcn::Function)

API function to set or change the callback function being executed upon a
file change. Can be "hot-swapped", i.e. while the file watcher is running.
The callback function receives a string with the file path and is not
expected to return anything.
"""
function set_callback(w::SimpleWatcher, callback::Function)
    prev_running = stop(w) # returns true if was running
    w.callback = callback
    prev_running && start(w) # start again if it was running before
end

"""
    isrunning(w::SimpleWatcher)

API function to check whether the file watcher is running. Should not be
required though, since the `start` and `stop` API functions work in any
case.
"""
isrunning(w::SimpleWatcher) = (w.task != nothing) && !istaskdone(w.task)

"""
    start(w::SimpleWatcher)

API function to start the file watcher.
"""
start(w::SimpleWatcher) = !isrunning(w) && (w.task = @async _file_watcher(w))

"""
    stop(w::SimpleWatcher)

API function to stop the file watcher. The list of files being watched is
preserved. Also, it still accepts new files to be watched by `watch_file`.
Once restarted with `start`, it continues watching the files in the list
(and will initially trigger the callback for all files that have changed
in the meantime). Returns a `Bool` indicating whether the watcher was
running before `stop` was called.
"""
function stop(w::SimpleWatcher)
    was_running = isrunning(w)
    if was_running
        schedule(w.task, InterruptException(), error=true)
        _waitfor_task_shutdown(w) # required to have consistent behaviour
    end
    return was_running
end


"""
    is_file_watched(w::SimpleWatcher, path::String)

API function to check whether a file is already being watched.
"""
is_file_watched(w::SimpleWatcher, path::String) = any(wf -> wf.path == path, w.filelist)
    # ~4x faster, if ever need be:
    # for wf ∈ w.filelist wf.path == path && return true end
    # return false


"""
    watch_file(w::SimpleWatcher, path::String)

API function to add a file to be watched for changes.
"""
# watch_file(w::SimpleWatcher, path::String) = isfile(path) && !is_file_watched(w, path) && push!(w.filelist, WatchedFile(path))
function watch_file(w::SimpleWatcher, path::String)
    if isfile(path) && !is_file_watched(w, path)
        push!(w.filelist, WatchedFile(path))
        println("ℹ [SimpleWatcher]: now watching '$path'")
    end
end
