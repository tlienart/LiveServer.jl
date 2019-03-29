"""
    FileWatcher

Contains a list of watched files and a callback function that should be applied in the case of file
events.
"""
struct FileWatcher
    watched_files::Dict{String,Task}
    callback::Function
    FileWatcher(cb::Function) = new(Dict{String,Task}(), cb)
end

"""
    _file_watcher(filepath, fw)

Helper function that's called asynchronously to act if a file has changed.
See also [`add_to_filewatcher`](@ref).
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
    add_to_filewatcher!(filewatcher, filepath)

Adds `filepath` to the FileWatcher `filewatcher` provided it is not already being watched.
"""
function add_to_filewatcher!(fw::FileWatcher, filepath::AbstractString)
    if filepath ∉ keys(fw.watched_files)
        fw.watched_files[filepath] = @async _file_watcher(filepath, fw)
    end
    return nothing
end

"""
    stop_tasks!(filewatcher)

Kill all file-watching tasks of a `FileWatcher`."
"""
function stop_tasks!(fw::FileWatcher)
    for (fp, tsk) ∈ fw.watched_files
        if tsk.state == :runnable
            schedule(tsk, [], error=true) # raise error in the task --> kills it
        end
    end
    empty!(fw.watched_files)
end
