"""
    WatchedFile

Struct for a file being watched containing the path to the file as well as the time of last
modification.
"""
mutable struct WatchedFile{T<:AbstractString}
    path::T
    mtime::Float64
end

"""
    WatchedFile(f_path)

Construct a new `WatchedFile` object around a file `f_path`.
"""
WatchedFile(f_path::AbstractString) = WatchedFile(f_path, mtime(f_path))


"""
    has_changed(wf::WatchedFile)

Check if a `WatchedFile` has changed. Returns -1 if the file does not exist, 0 if it does exist but
has not changed, and 1 if it has changed.
"""
function has_changed(wf::WatchedFile)
    isfile(wf.path) || return -1
    return Int(mtime(wf.path) > wf.mtime)
end

"""
    set_unchanged!(wf::WatchedFile)

Set the current state of a `WatchedFile` as unchanged"
"""
set_unchanged!(wf::WatchedFile) = wf.mtime = mtime(wf.path)


"""
    SimpleWatcher([callback]; sleeptime::Float64=0.1)

A simple file watcher. You can specify a callback function, receiving the path of each file that
has changed as an `AbstractString`, at construction or later by the API function described below.
The `sleeptime` is the time waited between to runs of the loop looking for changed files, it is
constrained to be at least 0.05s.

# API functions

It follows an overview on all API functions. Here, `w` is a `SimpleWatcher`.
The main API functions that are used by the live server, and thus are to be overloaded by external
file watchers and exported by default:

- `start(w)`: start the watcher
- `stop(w)`: stop the watcher; preserves the list of watched files and new files can still be added
using `watch_file!`
- `set_callback!(w, callback::Function)`: set callback to be executed upon file changes
- `watch_file!(w, filepath::AbstractString)`: add file to be watched

Further API functions (probably never used in a normal use case), not
exported by default:

- `isrunning(w)`: check whether the watcher is running
- `is_file_watched(w, filepath::AbstractString)`: check whether a file is being watched

# Examples
```julia
using LiveServer

# create a file, instantiate file watcher, add the file to be watched
write("textfile.txt", "A text file.")
w = SimpleWatcher(f -> println("File changed: \$f"))
watch_file!(w, "textfile.txt")

# start the watcher, change the file
start(w)
write("textfile.txt", "Changed text file.")
sleep(0.15) # make sure a file-check runs before changing callback

# change the callback function, change the file again, sstop the watcher
set_callback!(w, f -> println("Changed: \$f"))
write("textfile.txt", "Second-time changed text file.")
sleep(0.15)
stop(w)

# watcher does not add files that do not exist
watch_file!(w, "this_file_does_not_exist_at.all")

# let's remove the watched file and see if the watcher notices
rm("textfile.txt")
start(w)
sleep(0.15)
stop(w)
```
"""
mutable struct SimpleWatcher
    callback::Union{Nothing,Function} # callback function triggered upon file change
    task::Union{Nothing,Task}         # asynchronous file-watching task
    sleeptime::Float64                # sleep-time before checking for file changes
    watchedfiles::Vector{WatchedFile}     # list of files being watched
end

"""
    SimpleWatcher([callback]; sleeptime)

Instantiate a new `SimpleWatcher` with an optional callback triggered upon file change.
The `sleeptime` argument can be used to determine how often to check for file change (default is
every 0.1 second and minimum is 0.05).
"""
SimpleWatcher(callback::Union{Nothing,Function}=nothing; sleeptime::Float64=0.1) =
    SimpleWatcher(callback, nothing, max(0.05, sleeptime), Vector{WatchedFile}())


"""
    file_watcher!(w::SimpleWatcher)

Helper function that's spawned as an asynchronous task and checks for file changes. This task
is normally terminated upon an `InterruptException` and shows a warning in the presence of
any other exception.
"""
function file_watcher!(w::SimpleWatcher)
    try
        while true
            sleep(w.sleeptime)
            # only check files if there's a callback to call upon changes
            w.callback === nothing && continue

            # keep track of any files that may have been deleted
            deleted_files = []
            for (i, wf) ∈ enumerate(w.watchedfiles)
                changed_state = has_changed(wf)
                if changed_state == 1
                    set_unchanged!(wf)
                    w.callback(wf.path)
                elseif changed_state == -1
                    println("ℹ [SimpleWatcher]: file '$(wf.path)' does not exist, removing it from list")
                    push!(deleted_files, i)
                end
            end
            # remove deleted files from list of watched files
            deleteat!(w.watchedfiles, deleted_files)
        end
    catch EXC
        if !isa(EXC, InterruptException) # if interruption, normal termination
            @warn "Exception in file-watching task; please stop the server (Ctrl-C): " EXC
        end
    end
end


"""
    _waitfor_task_shutdown(w::SimpleWatcher)

Helper function ensuring that the `file_watcher!` task has ended
before continuing.
"""
function _waitfor_task_shutdown(w::SimpleWatcher)
    while !istaskdone(w.task)
        sleep(0.05)
    end
end


"""
    set_callback!(w::SimpleWatcher, callback::Function)

Mandatory API function to set or change the callback function being executed upon a
file change. Can be "hot-swapped", i.e. while the file watcher is running.
The callback function receives an `AbstractString` with the file path and is not
expected to return anything.
"""
function set_callback!(w::SimpleWatcher, callback::Function)
    prev_running = stop(w) # returns true if was running
    w.callback = callback
    prev_running && start(w) # start again if it was running before
end


"""
    isrunning(w::SimpleWatcher)

Optional API function to check whether the file watcher is running. Should not be
required though, since the `start` and `stop` API functions work in any
case.
"""
isrunning(w::SimpleWatcher) = (w.task != nothing) && !istaskdone(w.task)


"""
    start(w::SimpleWatcher)

Mandatory API function to start the file watcher.
"""
function start(w::SimpleWatcher)
    !isrunning(w) && (w.task = @async file_watcher!(w))
    # wait until task runs to ensure reliable start (e.g. if `stop` called right afterwards)
    while w.task.state != :runnable
        sleep(0.001)
    end
end


"""
    stop(w::SimpleWatcher)

Mandatory API function to stop the file watcher. The list of files being watched is
preserved. Also, it still accepts new files to be watched by `watch_file!`.
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
    is_file_watched(w::SimpleWatcher, filepath::AbstractString)

Optional API function to check whether a file is already being watched.
"""
is_file_watched(w::SimpleWatcher, filepath::AbstractString) = any(wf -> wf.path == filepath, w.watchedfiles)


"""
    watch_file!(w::SimpleWatcher, filepath::AbstractString)

Mandatory API function to add a file to be watched for changes.
"""
function watch_file!(w::SimpleWatcher, filepath::AbstractString)
    if isfile(filepath) && !is_file_watched(w, filepath)
        push!(w.watchedfiles, WatchedFile(filepath))
        println("ℹ [SimpleWatcher]: now watching '$filepath'")
    end
end
