module LiveServer

using HTTP
using FileWatching
using Sockets

export serve

# the script to be added to HTML files (NOTE: the random string is there to help make sure this
# script doesn't clash with other javascripts that may be on the page
const BROWSER_RELOAD_SCRIPT = """
    <!-- browser-reload script, automatically added by the LiveServer.jl -->
    <script type="text/javascript">
      var ws_M3sp9eAgRFN9y = new WebSocket("ws://" + location.host + location.pathname);
      ws_M3sp9eAgRFN9y.onmessage = function(msg) {
          // ws_M3sp9eAgRFN9y.send(browser.tabs.getCurrent().id)
          // ws_M3sp9eAgRFN9y.close();
          location.reload();
      };
    </script>
    """

# "List of files being tracked by WebSocket connections"
const WS_HTML_FILES = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()

include("file_watching.jl")
include("server.jl")

end
