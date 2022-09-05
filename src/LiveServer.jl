module LiveServer

import Sockets, Pkg, MIMEs
using Base.Filesystem

using HTTP

export serve, servedocs

#
# Environment variables
#

"""Script to insert on a page for live reload, see `client.html`."""
const BROWSER_RELOAD_SCRIPT = read(joinpath(@__DIR__, "client.html"), String)

"""Whether to display messages while serving or not, see [`verbose`](@ref)."""
const VERBOSE = Ref{Bool}(false)

"""The folder to watch, either the current one or a specified one (dir=...)."""
const CONTENT_DIR = Ref{String}("")

"""Relative path to a web dir (from CONTENT_DIR) when the user navigated to one."""
const WEB_DIR = Ref{String}("")

"""List of files being tracked with WebSocket connections."""
const WS_VIEWERS = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()

"""Keep track of whether an interruption happened while processing a websocket."""
const WS_INTERRUPT = Base.Ref{Bool}(false)

#
# Functions
#

include("file_watching.jl")
include("server.jl")

include("utils.jl")

end # module
