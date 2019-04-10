# Extending LiveServer

There may be circumstances where you will want the page-reloading to be triggered by your own mechanism.
As a very simple example, you may want to display your own custom messages every time a file is updated.
This page explains how to extend `SimpleWatcher <: FileWatcher` and, more generally, how to write your own `FileWatcher`

## Using `SimpleWatcher` with a custom callback

In most circumstances, using an instance of the `SimpleWatcher` type with your own _custom callback function_ is what you will want to do.

The `SimpleWatcher` does what you expect in terms of watching files it is told to watch and triggering a function (the _callback_) when a change is detected.
The callback function takes as argument the path of the file that was modified and returns nothing.

The base callback function ([`LiveServer.file_changed_callback`](@ref)) does only one thing: it sends a signal to the relevant viewers to trigger page reloads.
You will typically want to re-use `file_changed_callback` or copy its code.

As an example of a custom callback, here is a simple modified callback mechanism which prints `Hello!` before using the base callback function:

```julia
custom_callback(fp::AbstractString) = (println("Hello!"); file_changed_callback(fp))
```

A more sophisticated customised callback is the one that is used in [`servedocs`](@ref) (see [`servedocs_callback`](@ref)).
The callback has a different behaviour depending on which file is modified and does a few extra steps before signalling the viewers to reload appropriate pages.

## Writing your own `FileWatcher`

If you decide to write your own `FileWatcher` type, you will need to meet the API.
The easier is probably that you look at the code for `SimpleWatcher` and adapt it to your need.
Let's assume for now that you want to define a `CustomWatcher <: FileWatcher`.

### Fields

The only field that is _required_ by the rest of the code is

* `status`: a symbol that must be set to `:interrupted` upon errors in the file watching task

Likely you will want to have some (likely most) of the fields of a `SimpleWatcher` i.e.:

* `callback`: the callback function to be triggered upon an event,
* `task`: the asynchronous file watching task,
* `watchedfiles`: the vector of [`LiveServer.WatchedFile`](@ref) i.e. the paths to the file being watched as long as their time of last modification,
* `sleeptime`: the time to wait before going over the list of `watchedfiles` to check for events, you won't want this to be too small and it's lower bounded to `0.05` in `SimpleWatcher`.

Of course you can add any extra field you may want.

### Methods

Subsequently, your `CustomWatcher` may redefine some or all of the following methods (those that aren't will use the default method defined for all `FileWatcher`).

The methods that are _required_ by the rest of the code are

* `start(::FileWatcher)` and `stop(::FileWatcher)` to start and stop the watcher,
* `watch_file!(::FileWatcher, ::AbstractString)` to consider an additional file.

You may also want to re-define existing methods such as

* `file_watcher_task!(::FileWatcher)`: the loop that goes over the watched files, it checks for an event (modifications) and trigger the callback function; this will be the `CustomWatcher.task`. If errors happen in this asynchronous task, the `CustomWatcher.status` should be set to `:interrupted` so that all running tasks can be stopped properly.
* `set_callback!(::FileWatcher, ::Function)`: a helper function to bind a watcher with a callback function.
* `is_running(::FileWatcher)`: a helper function to check whether `CustomWatcher.task` is done.
* `is_watched(::FileWatcher, ::AbstractString)`: check if a file is watched by the watcher.

## Why not use `FileWatching`?

You may be aware of the [`FileWatching`](https://docs.julialang.org/en/v1/stdlib/FileWatching/index.html) module in `Base` and may wonder why we did not just use that one.
The main reasons we decided not to use it are:

* it triggers _a lot_: where our system only triggers the callback function upon _saving_ a file (e.g. you modified the file and saved the modification), `FileWatching` is more sensitive (for instance it will trigger when you _open_ the file),
* it is somewhat harder to make your own custom mechanisms to fire page reloads.

So ultimately, our system can be seen as a poor man's implementation of `FileWatching` that is robust, simple and easy to customise.
