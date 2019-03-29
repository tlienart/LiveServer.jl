"""
    FileWatcher

Can watch files for changes and fire callbacks upon events.
"""
struct FileWatcher
    "Array keeping track of all files being watched"
    watched_files::Dict{String,Task}

    "The callback, gets file path (`String`) and a `FileWatching.FileEvent` as arguments"
    callback::Function

    "Inner constructor: always initalise empty tasks-list"
    FileWatcher(cb::Function) = new(Dict{String,Task}(), cb)
end

"""
    _file_watcher(filepath, fw)

Helper function that's called asynchronously to act if a file has changed.
"""
function _file_watcher(filepath::AbstractString, fw::FileWatcher)
    fileevent = watch_file(filepath, -1) # returns upon a change

    # if file changed, start new task on this file (s.t. it is still being watched)
    if !fileevent.renamed && !fileevent.timedout
        fw.watched_files[filepath] = @async _file_watcher(filepath, fw)
    else
        # if renamed or timed out, remove from list of watched files
        delete!(fw.watched_files, filepath)
    end

    # fire user-specified callback
    fw.callback(filepath, fileevent)
end

"""
    start_watching(fw, filepath)

Tries to add the file `filepath` to the FileWatcher `fw`.
"""
function start_watching(fw::FileWatcher, filepath::AbstractString)
    if !isfile(filepath)
        println("⚠ File '$filepath' does not exist; not watching it.")
    elseif filepath ∈ keys(fw.watched_files)
        println("ℹ File '$filepath' is already being watched.")
    else
        fw.watched_files[filepath] = @async _file_watcher(filepath, fw)
    end
end

"""
    stop_tasks(fw)

Kill all file-watching tasks of a `FileWatcher`"
"""
function stop_tasks(fw::FileWatcher)
    for (fp, tsk) ∈ fw.watched_files
        if tsk.state == :runnable
            schedule(tsk, [], error=true) # raise error ∈ the task --> kills it
        end
    end
    empty!(fw.watched_files)
end
