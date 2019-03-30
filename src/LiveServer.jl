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
          ws_M3sp9eAgRFN9y.close();
          location.reload();
      };
    </script>
    """

###
### FILE HANDLING & RESPONSE
###

"""
    get_fpath(req_target)

Convert a requested target to a filesystem path and returns it provided the file exists. If it
doesn't, an empty string is returned.
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
it via a `Response(200, ...)` after injecting the browser reloading script if it is a HTML file.
The file is also added to the `f_watcher` dictionary if it isn't there already.
"""
function file_server!(f_watcher::Dict{String,Float64}, req::HTTP.Request)
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
    if f_path ∉ keys(f_watcher)
        f_watcher[f_path] = mtime(f_path)
    end

    # serving the file to the client (browser)
    return HTTP.Response(200, f_content)
end

###
### WEBSOCKET HANDLING & UPGRADE
###

"""
    ping_viewers!(wss)

Take a list of viewers (each a `WebSocket` associated with a watched file), filter out the viewers
that are unavailable and ping each of the viewer to trigger an upgrade request.
"""
function ping_viewers!(wss::Vector{HTTP.WebSockets.WebSocket}, ping::Bool=true)
    filter!(wsi -> wsi.io.c.io.status ∈ (Base.StatusActive, Base.StatusOpen), wss)
    foreach(wsi -> write(wsi, "ping"), wss)
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

###
### SERVE (main function)
###

"""
    serve(; ipaddr, port)

Main function to start a server at `http://ipaddr:port` and render what is in the current folder.

* `ipaddr` is either a string representing a valid IP address (e.g.: `"127.0.0.1"`) or an `IPAddr`
object (e.g.: `ip"127.0.0.1"`). You can also write `"localhost"` (default).
* `port` is an integer between 8000 (default) and 9000.

### Example

```julia
cd(joinpath(pathof(LiveServer), "example"))
serve()
```

If you open a browser to `localhost:8000`, you should see the `index.html` page from the `example`
folder being rendered.
"""
function serve(; ipaddr::Union{String, IPAddr}="localhost", port::Int=8000)
    # check arguments
    if isa(ipaddr, String)
        ipaddr == "localhost" || (ipaddr = parse(IPAddr, ipaddr))
    end
    8000 ≤ port ≤ 9000 || throw(ArgumentError("The port must be between 8000 and 9000."))

    # initiate a watcher: a dictionary which to each "watched file" associates a time of last
    # modification. So for instance ("/index.html", 1.553939219556752e9)
    f_watcher = Dict{String,Float64}()

    # initiate a websocket watcher: a dictionary which to each "viewed file" associates a list of
    # websockets corresponding to each of those viewers.
    ws_tracker = Dict{String,Vector{HTTP.WebSockets.WebSocket}}()

    # start listening
    saddr = "http://"
    if ipaddr == "localhost"
        saddr *= "localhost"
        ipaddr = ip"127.0.0.1"
    else
        saddr *= "$ipaddr"
    end
    println("✓ LiveServer listening on $saddr:$port... (use CTRL+C to shut down)")
    @async HTTP.listen(ipaddr, port) do http::HTTP.Stream
        if HTTP.WebSockets.is_upgrade(http.message)
            handle_upgrade!(ws_tracker, http)
        else
            # request
            HTTP.handle(HTTP.RequestHandlerFunction(req->file_server!(f_watcher, req)), http)
        end
    end

    # wait until user issues a CTRL+C command.
    try while true
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
                    ping_viewers!(ws_tracker[f_path])
                else
                    # e.g. css file may be needed by pages watched by any viewer so ping all
                    foreach(ping_viewers!, values(ws_tracker))
                end
            end
        end
        # allows to yield to the HTTP listener and also to not go crazy with the file checking
        sleep(0.1)
        end
    catch err
        if isa(err, InterruptException)
            # stop_watching!(f_watcher)
            empty!(f_watcher)
            empty!(ws_tracker)
        println("\n✓ LiveServer shut down.")
        else
            throw(err)
        end
    end
    return nothing
end


end
