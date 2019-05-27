# Internal Interface

Documentation for `LiveServer.jl`'s internal interface

## File watching

There are two key types related to file watching:

1. one to wrap a file being watched ([`LiveServer.WatchedFile`](@ref)),
2. one for the file watcher itself wrapping the list of watched files and what to do upon file changes ("callback" function)

Any file watcher will be a subtype of the abstract type [`LiveServer.FileWatcher`](@ref) with, for instance, the default watcher being [`LiveServer.SimpleWatcher`](@ref).

### WatchedFile

```@docs
LiveServer.WatchedFile
LiveServer.has_changed
LiveServer.set_unchanged!
```

### FileWatcher

####  Key types

```@docs
LiveServer.FileWatcher
LiveServer.SimpleWatcher
```

####  Functions related to a `FileWatcher`

```@docs
LiveServer.start
LiveServer.stop
LiveServer.set_callback!
LiveServer.watch_file!
LiveServer.file_watcher_task!
```

####  Additional helper functions:

```@docs
LiveServer.is_running
LiveServer.is_watched
```

## Live serving

The [`serve`](@ref) method instantiates a listener (`HTTP.listen`) in an asynchronous task.
The callback upon an incoming HTTP stream decides whether it is a standard HTTP request or a request for an upgrade to a websocket connection.
The former case is handled by [`LiveServer.serve_file`](@ref), the latter by
[`LiveServer.ws_tracker`](@ref).
Finally, [`LiveServer.file_changed_callback`](@ref) is the function passed to the file watcher to be executed upon file changes.

```@docs
LiveServer.serve_file
LiveServer.ws_upgrade
LiveServer.ws_tracker
LiveServer.file_changed_callback
```

#### Additional helper functions:

```@docs
LiveServer.get_fs_path
LiveServer.update_and_close_viewers!
```

#### Helper functions associated with `servedocs`

```@docs
LiveServer.servedocs_callback!
LiveServer.scan_docs!
```

## Miscellaneous

```@docs
LiveServer.example
LiveServer.setverbose
```
