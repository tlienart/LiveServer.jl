"""
Provides the [`serve`](@ref) command which runs a live server, and a simple
file-watcher [`SimpleWatcher`](@ref) which can also be used independently.
The main API functions of the latter are [`start`](@ref), [`stop`](@ref),
[`set_callback`](@ref), and [`watch_file`](@ref).

`LiveServer` depends on packages `HTTP` and `Sockets`.
"""
module LiveServer

using HTTP
using Sockets

export serve, verbose

# reference to the <script> tag to be added to HTML files; loads code from
# client.js when server starts (`serve()`)
const BROWSER_RELOAD_SCRIPT = Ref{String}()

const VERBOSE = Ref{Bool}(false)

# "List of files being tracked by WebSocket connections"
const WS_VIEWERS = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()

include("file_watching.jl")
include("server.jl")

"""
    verbose(b)

Set the verbosity to either true (showing messages) or false (default).
"""
verbose(b::Bool) = (VERBOSE.x = b)

"""
    example()

Simple function to copy an example website folder to the current working directory that can be
watched by the LiveServer to get an idea of how things work.

### Example

```julia
LiveServer.example()
cd("example")
serve()
```
"""
function example(; basedir="")
    isempty(basedir) && (basedir = pwd())
    cp(joinpath(dirname(dirname(pathof(LiveServer))), "example"), joinpath(basedir, "example"))
end

end # module
