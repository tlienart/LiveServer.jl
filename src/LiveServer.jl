module LiveServer

using HTTP
using FileWatching
using Sockets

export serve

# the script to be added to HTML files
const BROWSER_RELOAD_SCRIPT = """
    <!-- browser-reload script, automatically added by the LiveServer.jl -->
    <script type="text/javascript">
      var browser_reload_socket_M3sp9eAgRFN9y = new WebSocket("ws://" + location.host + location.pathname);
      browser_reload_socket_M3sp9eAgRFN9y.onmessage = function(msg) {
          browser_reload_socket_M3sp9eAgRFN9y.close();
          location.reload();
      };
    </script>
    """

# "List of files being tracked by WebSocket connections"
const WS_HTML_FILES = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()

include("file_watching.jl")
include("server.jl")

end
