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
set_unchanged!(wf::WatchedFile) = (wf.mtime = mtime(wf.path))


"""
    FileWatcher

Abstract Type for file watching objects such as [`SimpleWatcher`](@ref).
"""
abstract type FileWatcher end


"""
    SimpleWatcher([callback]; sleeptime::Float64=0.1) <: FileWatcher

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
- `is_watched(w, filepath::AbstractString)`: check whether a file is being watched

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
mutable struct SimpleWatcher <: FileWatcher
    callback::Union{Nothing,Function} # callback function triggered upon file change
    task::Union{Nothing,Task}         # asynchronous file-watching task
    sleeptime::Float64                # sleep-time before checking for file changes
    watchedfiles::Vector{WatchedFile} # list of files being watched
    status::Symbol                    # set to :interrupted as appropriate (caught by server)
end

"""
    SimpleWatcher([callback]; sleeptime)

Instantiate a new `SimpleWatcher` with an optional callback triggered upon file change.
The `sleeptime` argument can be used to determine how often to check for file change (default is
every 0.1 second and minimum is 0.05).
"""
SimpleWatcher(callback::Union{Nothing,Function}=nothing; sleeptime::Float64=0.1) =
    SimpleWatcher(callback, nothing, max(0.05, sleeptime), Vector{WatchedFile}(), :runnable)


"""
    file_watcher_task!(w::SimpleWatcher)

Helper function that's spawned as an asynchronous task and checks for file changes. This task
is normally terminated upon an `InterruptException` and shows a warning in the presence of
any other exception.
"""
function file_watcher_task!(fw::FileWatcher)
    try
        while true
            sleep(fw.sleeptime)

            # only check files if there's a callback to call upon changes
            fw.callback === nothing && continue

            # keep track of any file that may have been deleted
            deleted_files = Vector{Int}()
            for (i, wf) ∈ enumerate(fw.watchedfiles)
                state = has_changed(wf)
                if state == 0
                    continue
                elseif state == 1
                    # the file has changed, set it unchanged and trigger callback
                    set_unchanged!(wf)
                    fw.callback(wf.path)
                elseif state == -1
                    # the file does not exist, eventually delete it from list of watched files
                    VERBOSE.x && println("ℹ [SimpleWatcher]: file '$(wf.path)' does not exist " *
                                         " (anymore); removing it from list of watched files.")
                    push!(deleted_files, i)
                end
            end
            # remove deleted files from list of watched files
            deleteat!(fw.watchedfiles, deleted_files)
        end
    catch err
        fw.status = :interrupted
        # an InterruptException is the normal way for this task to end
        if !isa(err, InterruptException)
            @error "An error happened whilst watching files; shutting down. Error was: $err"
        end
        return nothing
    end
end


"""
    set_callback!(fw::FileWatcher, callback::Function)

Mandatory API function to set or change the callback function being executed upon a file change.
Can be "hot-swapped", i.e. while the file watcher is running.
"""
function set_callback!(fw::FileWatcher, callback::Function)
    prev_running = stop(fw)   # returns true if was running
    fw.callback  = callback
    prev_running && start(fw) # restart if it was running before
    fw.status = :runnable
    return nothing
end


"""
    isrunning(fw::FileWatcher)

Optional API function to check whether the file watcher is running.
"""
isrunning(fw::FileWatcher) = (fw.task !== nothing) && !istaskdone(fw.task)


"""
    start(w::FileWatcher)

Start the file watcher and wait to make sure the task has started.
"""
function start(fw::FileWatcher)
    isrunning(fw) || (fw.task = @async file_watcher_task!(fw))
    # wait until task runs to ensure reliable start (e.g. if `stop` called right afterwards)
    while fw.task.state != :runnable
        sleep(0.01)
    end
end


"""
    stop(fw::FileWatcher)

Stop the file watcher. The list of files being watched is preserved and new files can still be
added to the file watcher using `watch_file!`. It can be restarted with `start`.
Returns a `Bool` indicating whether the watcher was running before `stop` was called.
"""
function stop(fw::FileWatcher)
    was_running = isrunning(fw)
    if was_running
        schedule(fw.task, InterruptException(), error=true)
        # wait until sure the task is done
        while !istaskdone(fw.task)
            sleep(0.01)
        end
    end
    return was_running
end


"""
    is_watched(fw::FileWatcher, f_path::AbstractString)

Check whether a file `f_path` is being watched by file watcher `fw`.
"""
is_watched(fw::FileWatcher, f_path::AbstractString) = any(wf -> wf.path == f_path, fw.watchedfiles)


"""
    watch_file!(fw::FileWatcher, f_path::AbstractString)

Add a file to be watched for changes.
"""
function watch_file!(fw::FileWatcher, f_path::AbstractString)
    if isfile(f_path) && !is_watched(fw, f_path)
        push!(fw.watchedfiles, WatchedFile(f_path))
        VERBOSE.x && println("ℹ [SimpleWatcher]: now watching '$f_path'")
    end
end
