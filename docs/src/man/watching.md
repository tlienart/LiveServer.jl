# File watching

The file watching is considered an "internal" part of `LiveServer.jl`.
Nevertheless, you may use for other tasks than a live server. For this reason,
and for the people that want to get to know the structure of `LiveServer.jl`,
the main logic and functions are outlined here. For the details on the
internal stuff, have a look at the [Internal Interface](@ref).

## Logic
A single file being watched is represented by an object of type
[`LiveServer.WatchedFile`](@ref). There is two methods to check whether the
file has changed and to set the current state as "unchanged".

The watcher itself is defined as the abstract type [`LiveServer.FileWatcher`](@ref).
All API functions are implemented for this
abstract type. Every file watcher has to be a sub-type of `FileWatcher` and
thus may only change some of the API functions and use the "default" implementation
for the others. `LiveServer.jl`'s default watcher is [`LiveServer.SimpleWatcher`](@ref).
It just uses all of the default API-function implementations. That is, none
of them are specialised for `SimpleWatcher`, and thus the ones defined for
`FileWatcher` are dispatched.

The watcher is started using [`LiveServer.start`](@ref). This command
spawns an asynchronous task running in an infinite loop that checks the
watched files for changes. Unsurprisingly, [`LiveServer.stop`](@ref) stops
this loop. Now, what's left to do is to tell the watcher which files should
be observed, and what the reaction to a change should be.

Files to be watched can be added using [`LiveServer.watch_file!`](@ref).
The watcher checks whether the file is already watched and thus will not add
it twice to its list. Also, renamed or deleted files are automatically
removed from the list of watched files. You can add files while the
watcher is running or stopped.

Finally, you can pass a callback function to the file watcher, which is fired
whenever a file changes. Just pass a function receiving an `AbstractString` as
argument to [`LiveServer.set_callback!`](@ref). The string contains the
path to the file (including its name and extension). In the context of the
live server, this callback function triggers a page reload in the browsers
viewing a HTML page.

## Example
This is an example illustrating the API and all features of the default
`SimpleWatcher`.

```julia
using LiveServer: SimpleWatcher, start, stop, set_callback!, watch_file!, verbose
verbose(true) # run in verbose mode to see information about watched files

# create a file, instantiate file watcher, add the file to be watched
write("textfile.txt", "A text file.")
w = SimpleWatcher(f -> println("File changed: $f"))
watch_file!(w, "textfile.txt")

# start the watcher, change the file
start(w)
write("textfile.txt", "Changed text file.")
sleep(0.15) # make sure a file-check runs before changing callback

# change the callback function, change the file again, sstop the watcher
set_callback!(w, f -> println("Changed: $f"))
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

## Implementing your own file watcher
[coming soon...]
