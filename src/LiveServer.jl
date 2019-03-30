module LiveServer

using HTTP
using FileWatching
using Sockets

using Crayons

export serve

const LOGGER = Ref{Bool}(true)

setlogger(b::Bool) = (LOGGER.x = b)
function info(m::String, actor::Symbol=:none)
    if LOGGER.x
        crayon = Crayon(reset=true)
        if actor == :client
            crayon = Crayon(foreground=(226,242,145))
        elseif actor == :server
            crayon = Crayon(foreground=(205,145,242))
        else
            actor = ""
        end
        print(crayon, "ℹ $actor: $m")
        print(Crayon(reset=true), "\n")
    end
end
# the script to be added to HTML files (NOTE: the random string is there to help make sure this
# script doesn't clash with other javascripts that may be on the page
const BROWSER_RELOAD_SCRIPT = """
    <!-- browser-reload script, automatically added by the LiveServer.jl -->
    <script type="text/javascript">
      var ws_M3sp9eAgRFN9y = new WebSocket("ws://" + location.host + location.pathname);
      ws_M3sp9eAgRFN9y.onmessage = function(msg) {
          // ws_M3sp9eAgRFN9y.send(browser.tabs.getCurrent().id)
          ws_M3sp9eAgRFN9y.close();
          location.reload();
      };
    </script>
    """

# "List of files being tracked by WebSocket connections"
const WS_HTML_FILES = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()

include("file_watching.jl")
include("server.jl")

end
