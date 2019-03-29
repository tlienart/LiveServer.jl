"""
    filter_available_viewers!(wss, ping)

Take a list of viewers (each a `WebSocket` associated with a watched file), filter out the viewers
that are unavailable and if `ping` is set to `true`, ping each of the viewer to trigger an upgrade
request.
"""
function filter_available_viewers!(wss::Vector{HTTP.WebSockets.WebSocket}, ping::Bool=true)
    filter!(wsi -> wsi.io.c.io.status ∈ (Base.StatusActive, Base.StatusOpen), wss)
    ping && foreach(wsi -> write(wsi, "ping"), wss)
    return nothing
end


"""
    file_changed_callback(filepath, ev)

Callback that gets fired once a change to a file `filepath` is detected (FileEvent `ev`).
"""
function file_changed_callback(filepath::AbstractString, ev::FileWatching.FileEvent)
    # only do something if file was changed ONLY
    if ev.changed && !ev.renamed && !ev.timedout
        if lowercase(splitext(filepath)[2]) ∈ (".html", ".htm")
            # if html file, update viewers of this file only
            filter_available_viewers!(WS_HTML_FILES[filepath])
        else
            # otherwise (e.g. modification to a CSS file), update all viewers
            foreach(filter_available_viewers!, values(WS_HTML_FILES))
        end
    end
end

"""
    get_file(filepath)

Get filesystem path to requested file, or `nothing` if the file does not exist.
"""
function get_file(filepath::AbstractString)
    # TODO: ensure this is ok on windows.
    (filepath[1] == '/') && (filepath = "."*filepath)

    if filepath[end] == '/'
        # have to check for index.html. Assume index has standard `.html` extension.
        phtml = joinpath(filepath, "index.html")
        isfile(phtml) && return phtml
        # otherwise return nothing
        return nothing
    else
        return ifelse(isfile(filepath), filepath, nothing)
    end
end

"""
    file_server!(req, filewatcher)

Handler function for serving files. This takes a request (e.g. a path entered in a tab of the
browser), and converts it to the appropriate file system path. If the path corresponds to a HTML
file, it will inject the reloading script (see [`BROWSER_RELOAD_SCRIPT`](@ref)) at the end of it.
All files will then be added to the `filewatcher` (if they are not already being watched).
Finally the file will be served via a 200 (successful) response.
See also [`add_to_filewatcher!`](@ref).
"""
function file_server!(filewatcher::FileWatcher, req::HTTP.Request)
    fs_filepath = get_file(req.target)

    if fs_filepath == nothing
        return HTTP.Response(404, "404 not found")
    else
        file_content = read(fs_filepath, String)
        # if html, add the browser-sync script to it
        if splitext(fs_filepath)[2] == ".html"
            end_of_body_match = match(r"</body>", file_content)
            if end_of_body_match === nothing
                # TODO: better handling of this case
                throw(ErrorException("Could not find a closing `</body>` tag before which " *
                                     "to inject the reloading script."))
            else
                end_of_body = prevind(file_content, end_of_body_match.offset)
                # reconstruct the page with the reloading script
                io = IOBuffer()
                write(io, file_content[1:end_of_body])
                write(io, BROWSER_RELOAD_SCRIPT)
                write(io, file_content[nextind(file_content, end_of_body):end])
                file_content = String(take!(io))
            end
        end
        add_to_filewatcher!(filewatcher, fs_filepath)
        return HTTP.Response(200, file_content)
    end
end

"""
    ws_tracker(http)

The WebSocket tracker -- upgrades HTTP request to WS.
"""
function ws_tracker(http::HTTP.Stream)
    # +/- copy-paste from HTTP.WebSockets.upgrade ..............................
    if !HTTP.hasheader(http, "Sec-WebSocket-Version", "13")
        throw(HTTP.WebSocketError(0, "Expected \"Sec-WebSocket-Version: 13\"!\n" *
                                     "$(http.message)"))
    end

    HTTP.setstatus(http, 101)
    HTTP.setheader(http, "Upgrade" => "websocket")
    HTTP.setheader(http, "Connection" => "Upgrade")
    key = HTTP.header(http, "Sec-WebSocket-Key")
    HTTP.setheader(http, "Sec-WebSocket-Accept" => HTTP.WebSockets.accept_hash(key))
    HTTP.startwrite(http)

    io = http.stream
    ws = HTTP.WebSockets.WebSocket(io; server=true)
    # end copy-paste ...........................................................

    # add to list of html files being "watched"
    filepath = get_file(http.message.target)
    if filepath === nothing
        # should not happen, since WS request comes from just served file...
        throw(ErrorException("WebSocket request from inexistent file at path "*
                             "'$(http.message.target)'."))
    end

    # if the file is already being watched, add ws to it (e.g. several tabs); otherwise add to dict
    # note, nonresponsive ws will be eliminated by update_viewers
    if filepath ∈ keys(WS_HTML_FILES)
        push!(WS_HTML_FILES[filepath], ws)
    else
        WS_HTML_FILES[filepath] = [ws]
    end
    return nothing
end

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
        if ipaddr == "localhost"
            ipaddr = ip"0.0.0.0"
        else
            ipaddr = parse(IPAddr, ipaddr)
        end
    end
    8000 ≤ port ≤ 9000 || throw(ArgumentError("The port must be between 8000 and 9000."))

    # start a filewatcher which, for any file-event, will call `file_changed_callback`
    filewatcher = FileWatcher(file_changed_callback)

    # start listening
    saddr = "http://"
    if ipaddr == "localhost"
        saddr *= "localhost"
        ipaddr = ip"127.0.0.1"
    else
        saddr *= "$ipaddr"
    end
    println("✓ LiveServer listening on $saddr:$port... (use CTRL+C to shut down)")
    listener = @async HTTP.listen(ipaddr, port) do http::HTTP.Stream
        if HTTP.WebSockets.is_upgrade(http.message)
            # upgrade
            ws_tracker(http)
        else
            # request
            HTTP.handle(HTTP.RequestHandlerFunction(req->file_server!(filewatcher, req)), http)
        end
    end

    # wait until user issues a CTRL+C command.
    try while true
        sleep(0.1)
        end
    catch err
        if isa(err, InterruptException)
            # NOTE ideally here we would also want to stop the listener. However this is
            # not as easy as stopping the file watching tasks.
            stop_tasks!(filewatcher)
            empty!(WS_HTML_FILES)
        println("\n✓ LiveServer shut down.")
        else
            throw(err)
        end
    end
    return nothing
end
