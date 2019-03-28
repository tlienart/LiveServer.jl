module LiveServer

using HTTP
using Sockets
using FileWatching

export serve

include("file_watching.jl")
include("server.jl")

end # module
