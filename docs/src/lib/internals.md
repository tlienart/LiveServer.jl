# Internal Interface

Documentation for `LiveServer.jl`'s internal interface


## Internals for file watching

There is two types related to file watching, one for a single file being
watched ([`LiveServer.WatchedFile`](@ref)), the other for the watcher itself. The latter
is an abstract type [`LiveServer.FileWatcher`](@ref). All API functions are implemented for this
abstract type, and [`LiveServer.SimpleWatcher`](@ref) is `LiveServer.jl`'s default watcher that
is a sub-type of `FileWatcher` for which no specific API methods are defined.

### Watched file
```@docs
LiveServer.WatchedFile
LiveServer.has_changed
LiveServer.set_unchanged!
```

### File watcher
These are the two types and the API functions:
```@docs
LiveServer.FileWatcher
LiveServer.SimpleWatcher
LiveServer.start
LiveServer.stop
LiveServer.set_callback!
LiveServer.watch_file!
LiveServer.file_watcher_task!
```

There are also some helper functions:
```@docs
LiveServer.isrunning
LiveServer.is_watched
```

## Internals for live serving
The exported [`serve`](@ref) and [`verbose`](@ref) functions are not stated
again. The `serve` method instantiates a listener (`HTTP.listen`) in an
asynchronous task. The callback upon an incoming HTTP stream decides whether
it is a standard HTTP request or a request for an upgrade to a websocket
connection. The former case is handled by [`LiveServer.serve_file`](@ref), the latter by
[`LiveServer.ws_tracker`](@ref). Finally, [`LiveServer.file_changed_callback`](@ref) is the
function passed to the file watcher to be executed upon file changes.
```@docs
LiveServer.serve_file
LiveServer.ws_tracker
LiveServer.file_changed_callback
```

Also here, there's some helper functions:
```@docs
LiveServer.get_fs_path
LiveServer.update_and_close_viewers!
```
