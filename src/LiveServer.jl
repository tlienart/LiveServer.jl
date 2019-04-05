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

export serve, SimpleWatcher, start, stop, set_callback!, watch_file!

# the script to be added to HTML files
const BROWSER_RELOAD_SCRIPT = """
    <!-- browser-reload script, automatically added by the LiveServer.jl -->
    <script type="text/javascript">
      var ws_M3sp9eAgRFN9y = new WebSocket("ws://" + location.host + location.pathname);
      ws_M3sp9eAgRFN9y.onmessage = function(msg) {
          if(msg.data === "update"){
              ws_M3sp9eAgRFN9y.close();
              location.reload();
          }
      };
    </script>
    """


# "List of files being tracked by WebSocket connections"
const WS_HTML_FILES = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()

include("file_watching.jl")
include("server.jl")

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
