module LiveServer

using HTTP
using Sockets

export serve, stop

# the script to be added to HTML files (NOTE: the random string is there to help make sure this
# script doesn't clash with other javascripts that may be on the page
const BROWSER_RELOAD_SCRIPT = """
    <!-- browser-reload script, automatically added by the LiveServer.jl -->
    <script type="text/javascript">
      var ws_M3sp9eAgRFN9y = new WebSocket("ws://" + location.host + location.pathname);
      ws_M3sp9eAgRFN9y.onmessage = function(msg) {
          location.reload();
      };
    </script>
    """

const TASKS = Dict{Symbol,Task}()
const ISHANDLED = Ref{Bool}(false)

###
### FILE HANDLING & RESPONSE
###

"""
    get_fpath(req_target)

Convert a requested target to a filesystem path and returns it provided the file exists. If it
doesn't, an empty string is returned. See also [`file_server!`](@ref).
"""
function get_fpath(f_path::AbstractString)
    # TODO: ensure this is ok on windows.
    (f_path[1] == '/') && (f_path = "." *  f_path)
    if f_path[end] == '/'
        # have to check for index.html. Assume index has standard `.html` extension.
        phtml = joinpath(f_path, "index.html")
        isfile(phtml) && return phtml
        # otherwise return nothing
        return ""
    else
        return ifelse(isfile(f_path), f_path, "")
    end
end

"""
    file_server!(f_watcher, req)

Handler function for serving files. This takes a request for a specific file, finds it and serves
it via a `Response(200, ...)` after appending the browser reloading script if it is a HTML file.
The file is also added to the `f_watcher` dictionary if it isn't there already.
"""
function file_server!(f_watcher::Dict{String,Float64}, req::HTTP.Request)
    # retrieve the file
    f_path = get_fpath(req.target)
    isempty(f_path) && return HTTP.Response(404, "404! File not found or server down.")
    f_content = read(f_path, String)

    # if html, add the browser-sync script to it
    if splitext(f_path)[2] == ".html"
        end_body_match = match(r"</body>", f_content)
        if end_body_match === nothing
            # no </body> tag found, trying to add the reload script at the end; this may fail.
            f_content *= BROWSER_RELOAD_SCRIPT
        else
            end_body = prevind(f_content, end_body_match.offset)
            # reconstruct the page with the reloading script
            io = IOBuffer()
            write(io, f_content[1:end_body])
            write(io, BROWSER_RELOAD_SCRIPT)
            write(io, f_content[nextind(f_content, end_body):end])
            f_content = String(take!(io))
        end
    end

    # add the file to the file watcher if it isn't there already
    f_path ∈ keys(f_watcher) || (f_watcher[f_path] = mtime(f_path))

    # serve the file to the client (browser)
    return HTTP.Response(200, f_content)
end

###
### WEBSOCKET HANDLING & UPGRADE
###

"""
    message_viewers!(wss)

Take a list of viewers (each a `WebSocket` associated with a watched file), send a message with
data "update" and subsequently close the websocket and clear the list of viewers. Upon receiving
the message, the BROWSER_RELOAD_SCRIPT appended to the webpage(s) will trigger a page reload.
"""
function message_viewers!(wss::Vector{HTTP.WebSockets.WebSocket}, ping::Bool=true)
    foreach(wss) do wsi
        write(wsi, "update")
        close(wsi.io)
    end
    empty!(wss)
    return nothing
end

"""
    handle_upgrade!(http)

Upon a websocket upgrade request triggered after serving a file, this function launches a new
websocket and appends it to the list of websockets currently associated with the file.
"""
function handle_upgrade!(ws_tracker, http::HTTP.Stream)
    # adapted from HTTP.WebSockets.upgrade; note that here the upgrade will always have
    #  the right format as it always triggered by after a Response
    HTTP.setstatus(http, 101)
    HTTP.setheader(http, "Upgrade" => "websocket")
    HTTP.setheader(http, "Connection" => "Upgrade")
    key = HTTP.header(http, "Sec-WebSocket-Key")
    HTTP.setheader(http, "Sec-WebSocket-Accept" => HTTP.WebSockets.accept_hash(key))
    HTTP.startwrite(http)
    ws = HTTP.WebSockets.WebSocket(http.stream; server=true)

    # add to list of html files being "watched"
    # NOTE this file exists because this upgrade has been triggered after serving it.
    f_path = get_fpath(http.message.target)

    # keep track of the newly opened websocket by appending it to the list of websockets
    # associated with the file
    if f_path ∈ keys(ws_tracker)
        push!(ws_tracker[f_path], ws)
    else
        ws_tracker[f_path] = [ws]
    end
    return nothing
end

"""
    watcher!(f_watcher, ws_tracker, server)

Go continuously over the watched files (`f_watcher`) and check if a file was recently changed.
If so, message the relevant viewers associated with the file (so that a page reload is triggered).
The watcher is normally stopped with an InterruptException (CTRL+C).
"""
function watcher!(f_watcher, ws_tracker, server)
    try
        while true
            # go over the files currently being watched
            for (f_path, time) ∈ f_watcher
                # check if the file still exists, if it doesn't remove from f_watcher
                isfile(f_path) || (delete!(f_watcher, f_path); continue)
                # retrieve the time of last modification
                cur_mtime = mtime(f_path)
                # check how it compares to the previously recorded time, if smaller --> update
                if f_watcher[f_path] < cur_mtime
                    # update time of last modif
                    f_watcher[f_path] = cur_mtime
                    # trigger browser upgrade as appropriate
                    if splitext(f_path)[2] == ".html"
                        message_viewers!(ws_tracker[f_path])
                    else
                        # e.g. css file may be needed by pages watched by any viewer so ping all
                        foreach(message_viewers!, values(ws_tracker))
                    end
                end
            end
            # yield to other tasks (namely to the HTTP listener)
            sleep(0.1)
        end
    catch err
        handle_error(err, f_watcher, ws_tracker, server)
    end
    return nothing
end

###
### SERVE (main function)
###

"""
    serve(; host, port, wait)

Main function to start a server at `http://host:port` and render what is in the current folder.

* `host="localhost"` is either a string representing a valid IP address (e.g.: `"127.0.0.1"`) or an
`IPAddr` object (e.g.: `ip"127.0.0.1"`).
* `port=8000` is an integer between 8000 and 9000 associated with the port that must be used.

### Example

```julia
cd(joinpath(pathof(LiveServer), "example"))
serve()
```

If you open a browser to `localhost:8000`, you should see the `index.html` page from the `example`
folder being rendered.
"""
function serve(; port::Int=8000)
    # check port
    8000 ≤ port ≤ 9000 || throw(ArgumentError("The port must be between 8000 and 9000."))

    # initiate a watcher: a dictionary which to each "watched file" associates a time of last
    # modification. So for instance ("/index.html", 1.553939219556752e9)
    f_watcher = Dict{String,Float64}()

    # initiate a websocket watcher: a dictionary which to each "viewed file" associates a list of
    # websockets corresponding to each of those viewers.
    ws_tracker = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()

    # initiate a server
    server = Sockets.listen(port)

    # start listening
    println("✓ LiveServer listening on http://localhost:$port... (use CTRL+C to shut down)")
    TASKS[:listener] = @async begin
        HTTP.listen(ip"127.0.0.1", port; server=server, readtimeout=0) do http::HTTP.Stream
            if server.status != 4
                return 0
            end
            if HTTP.WebSockets.is_upgrade(http.message)
                handle_upgrade!(ws_tracker, http)
            else
                HTTP.handle(HTTP.RequestHandlerFunction(req->file_server!(f_watcher, req)), http)
            end
        end
    end

    # launch the file watching loop
    watcher!(f_watcher, ws_tracker, server)

    return nothing
end

###
### HANDLE ERROR
###

"""
    handle_error(err, f_watcher, ws_tracker)

Helper function to handle an error thrown in the [`serve`](@ref) function. If it is an
InterruptException (user pressed CTRL+C), clean up and end  program. Otherwise re-throw the error.
"""
function handle_error(err, f_watcher, ws_tracker, server)
    if isa(err, InterruptException)
        print("\n✓ LiveServer shutting down...")
        # try to close any remaining websocket
        for wss ∈ values(ws_tracker)
            for wsi ∈ wss
                close(wsi.io)
            end
        end
        # empty tracking dictionaries
        empty!.((f_watcher, ws_tracker))
        # close the server
        close(server)
        println("")
    else
        throw(err)
    end
    return nothing
end

end # module
