module LiveServer

# from stdlib
using Sockets, Pkg
# the only dependency (see the patch in http_patch.jl)
using HTTP

export serve, servedocs

#
# Environment variables
#

"""Script to insert on a page for live reload, see `client.html`."""
const BROWSER_RELOAD_SCRIPT = read(joinpath(@__DIR__, "client.html"), String)

"""Whether to display messages while serving or not, see [`verbose`](@ref)."""
const VERBOSE = Ref{Bool}(false)

"""The folder to watch, either the current one or a specified one."""
const CONTENT_DIR = Ref{String}("")

"""List of files being tracked with WebSocket connections."""
const WS_VIEWERS = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()

"""Keep track of whether an interruption happened while processing a websocket."""
const WS_INTERRUPT = Base.Ref{Bool}(false)

# to fix lots of false error messages from HTTP
# https://github.com/JuliaWeb/HTTP.jl/pull/546
# we do HTTP.Stream{HTTP.Messages.Request,S} instead of just HTTP.Stream to prevent the Julia warning about incremental compilation
# This hack was kindly suggested by Fons van der Plas, the author of Pluto.jl see
# https://github.com/fonsp/Pluto.jl/commit/34d41e63138ee6dad178cd9916d4721441eaf710
function HTTP.closebody(http::HTTP.Stream{HTTP.Messages.Request,S}) where S <: IO
    http.writechunked || return
    http.writechunked = false
    try; write(http.stream, "0\r\n\r\n"); catch; end
    return
end

#
# Functions
#

include("mimetypes.jl")
include("file_watching.jl")
include("server.jl")

include("utils.jl")

if Base.VERSION >= v"1.4.2"
    include("precompile.jl")
    _precompile_()
end

end # module
