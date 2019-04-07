"""
Provides the [`serve`](@ref) command which runs a live server, and a simple
file-watcher [`SimpleWatcher`](@ref) which can also be used independently.
The main API functions of the latter are [`start`](@ref), [`stop`](@ref),
[`set_callback`](@ref), and [`watch_file`](@ref).

`LiveServer` depends on the `HTTP.jl` package.
"""
module LiveServer

using HTTP
using Sockets # this is in stdlib

export serve, verbose

const BROWSER_RELOAD_SCRIPT = read(joinpath(dirname(pathof(LiveServer)), "client.html"), String)
const VERBOSE = Ref{Bool}(false)

# list of files being tracked by WebSocket connections, interrupt catched in ws handler?
const WS_VIEWERS = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()
const WS_ERROR = Base.Ref{Bool}(false)

include("file_watching.jl")
include("server.jl")

#
# Utilities
#

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
