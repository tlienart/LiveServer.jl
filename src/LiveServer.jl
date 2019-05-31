module LiveServer

# from stdlib
using Sockets
# the only dependency (see the patch in http_patch.jl)
using HTTP

export serve, servedocs

#
# Environment variables
#

"""Script to insert on a page for live reload, see `client.html`."""
const BROWSER_RELOAD_SCRIPT = read(joinpath(dirname(pathof(LiveServer)), "client.html"), String)

"""Whether to display messages while serving or not, see [`verbose`](@ref)."""
const VERBOSE = Ref{Bool}(false)

"""The folder to watch, either the current one or a specified one."""
const CONTENT_DIR = Ref{String}("")

"""List of files being tracked with WebSocket connections."""
const WS_VIEWERS = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()

"""Keep track of whether an interruption happened while processing a websocket."""
const WS_INTERRUPT = Base.Ref{Bool}(false)

#
# Functions
#

include("mimetypes.jl")
include("file_watching.jl")
include("server.jl")

include("utils.jl")

end # module
