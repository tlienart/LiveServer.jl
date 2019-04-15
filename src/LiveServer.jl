module LiveServer

# from stdlib
using Sockets
# the only dependency (see the patch in http_patch.jl)
using HTTP

export serve, servedocs

#
# Environment variables
#

# see `client.html`
const BROWSER_RELOAD_SCRIPT = read(joinpath(dirname(pathof(LiveServer)), "client.html"), String)
# whether to display messages while serving or not, see `verbose()`
const VERBOSE = Ref{Bool}(false)
# the folder to watch, either the current one or a specified one.4
const CONTENT_DIR = Ref{String}("")
# list of files being tracked by WebSocket connections, interrupt catched in ws handler?
const WS_VIEWERS = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()
# keep track of whether an interruption happened while processing a websocket
const WS_INTERRUPT = Base.Ref{Bool}(false)

#
# HTTP patch
#
include("http_patch.jl")

#
# Core
#

include("file_watching.jl")
include("server.jl")

#
# Utilities
#

include("utils.jl")

end # module
