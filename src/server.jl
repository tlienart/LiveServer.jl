"""
    update_and_close_viewers!(wss::Vector{HTTP.WebSockets.WebSocket})

Take a list of viewers, i.e. WebSocket connections from a client,
send a message with data "update" to each of them (to trigger a page reload),
then close the connection. Finally, empty the list since all connections are
closing anyway and clients will re-connect from the re-loaded page.
"""
function update_and_close_viewers!(wss::Vector{HTTP.WebSockets.WebSocket})
    foreach(wss) do wsi
        write(wsi, "update")
        close(wsi.io)
    end
    empty!(wss)
    return nothing
end


"""
    file_changed_callback(filepath::AbstractString)

Function reacting to the change of a file `filepath`. Is set as callback for the file watcher.
"""
function file_changed_callback(f_path::AbstractString)
    VERBOSE.x && println("ℹ [LiveUpdater]: Reacting to change in file '$f_path'...")
    if endswith(f_path, ".html")
        # if html file, update viewers of this file only
        update_and_close_viewers!(WS_HTML_FILES[f_path])
    else
        # otherwise (e.g. modification to a CSS file), update all viewers
        foreach(update_and_close_viewers!, values(WS_HTML_FILES))
    end
    return nothing
end


"""
    get_fs_path(req_path::AbstractString)

Return the filesystem path corresponding to a requested path, or an empty String if the file
was not found.
"""
function get_fs_path(req_path::AbstractString)::String
    # first element after the split is **always** "/"
    r_parts = split(HTTP.URI(req_path).path[2:end], "/")
    fs_path = joinpath(r_parts...)
    # if no file is specified, try to append `index.html` and see
    endswith(req_path, "/") && (fs_path = joinpath(fs_path, "index.html"))
    # either the result is a valid file path in which case it's returned otherwise ""
    return ifelse(isfile(fs_path), fs_path, "")
end


"""
    serve_file(fw, req::HTTP.Request)

Handler function for serving files. This takes a file watcher, to which
files to be watched can be added, and a request (e.g. a path entered in a tab of the
browser), and converts it to the appropriate file system path. If the path corresponds to a HTML
file, it will inject the reloading script (see [`BROWSER_RELOAD_SCRIPT`](@ref)) at the end
of its body, i.e. directly before the </body> tag.
All files served are added to the file watcher, which is responsible
to check whether they're already watched or not.
Finally the file is served via a 200 (successful) response. If the file does
not exist, a response with status 404 and message "404 not found" is sent.
"""
function serve_file(fw, req::HTTP.Request)
    fs_path = get_fs_path(req.target)
    # in case the path was not resolved, return a 404
    isempty(fs_path) && return HTTP.Response(404, "404: file not found.")

    content = read(fs_path, String)
    # if html, add the browser-sync script to it
    if splitext(fs_path)[2] == ".html"
        end_body_match = match(r"</body>", content)
        if end_body_match === nothing
            # no </body> tag found, trying to add the reload script at the end; this may fail.
            content *= BROWSER_RELOAD_SCRIPT
        else
            end_body = prevind(content, end_body_match.offset)
            # reconstruct the page with the reloading script
            io = IOBuffer()
            write(io, SubString(content, 1:end_body))
            write(io, BROWSER_RELOAD_SCRIPT)
            write(io, SubString(content, nextind(content, end_body):lastindex(content)))
            content = take!(io)
        end
    end
    # add this file to the file watcher, send content to client
    watch_file!(fw, fs_path)
    return HTTP.Response(200, content)
end


"""
    ws_tracker(::HTTP.Stream)

The websocket tracker. Upgrades the HTTP request in the stream to a websocket
and adds this connection to the viewers in the global dictionary
`WS_HTML_FILES`.
"""
function ws_tracker(http::HTTP.Stream)
    # adapted from HTTP.WebSockets.upgrade; note that here the upgrade will always have
    # the right format as it always triggered by after a Response
    HTTP.setstatus(http, 101)
    HTTP.setheader(http, "Upgrade" => "websocket")
    HTTP.setheader(http, "Connection" => "Upgrade")
    key = HTTP.header(http, "Sec-WebSocket-Key")
    HTTP.setheader(http, "Sec-WebSocket-Accept" => HTTP.WebSockets.accept_hash(key))
    HTTP.startwrite(http)

    io = http.stream
    ws = HTTP.WebSockets.WebSocket(io; server=true)

    # add to list of html files being "watched"
    # NOTE: this file always exists because the query is generated just after serving it
    filepath = get_fs_path(http.message.target)

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
    serve(fw::FileWatcher=SimpleWatcher(); port::Int)

Main function to start a server at `http://localhost:port` and render what is in the current
directory. (See also [`example`](@ref) for an example folder).

* `filewatcher` is a file watcher implementing the API described for [`SimpleWatcher`](@ref) and
messaging the viewers (web sockets) upon detecting file changes.
* `port` is an integer between 8000 (default) and 9000.

# Example

```julia
LiveServer.example()
cd("example")
serve()
```

If you open a browser to `http://localhost:8000`, you should see the `index.html` page from the
`example` folder being rendered. If you change the file, the browser will automatically reload the
page and show the changes.
"""
function serve(fw::FileWatcher=SimpleWatcher(); port::Int=8000)
    8000 ≤ port ≤ 9000 || throw(ArgumentError("The port must be between 8000 and 9000."))

    # set the callback and start the file watcher
    set_callback!(fw, file_changed_callback)
    start(fw)

    # make request handler
    req_handler = HTTP.RequestHandlerFunction(req -> serve_file(fw, req))

    server = Sockets.listen(port)
    println("✓ LiveServer listening on http://localhost:$port...\n  (use CTRL+C to shut down)")
    @async HTTP.listen(Sockets.localhost, port, server=server, readtimeout=0) do http::HTTP.Stream
        if HTTP.WebSockets.is_upgrade(http.message)
            # upgrade to websocket
            ws_tracker(http)
        else
            # handle HTTP request
            HTTP.handle(req_handler, http)
        end
    end

    # wait until user interrupts the LiveServer (using CTRL+C).
    try while true
        sleep(0.1)
        (fw.status == :interrupted) && throw(InterruptException())
        end
    catch err
        if isa(err, InterruptException)
            VERBOSE.x && println("\n⋮ shutting down LiveServer")

            stop(fw)
            # close any remaining websockets
            for wss ∈ values(WS_HTML_FILES), wsi ∈ wss
                close(wsi.io)
            end
            empty!(WS_HTML_FILES)

            close(server) # shut down server
            VERBOSE.x && println("\n✓ LiveServer shut down.")
        else
            throw(err)
        end
    end
    return nothing
end
