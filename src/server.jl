"""
    update_and_close_viewers!(wss::Vector{HTTP.WebSockets.WebSocket})

Take a list of viewers, i.e. WebSocket connections from a client,
send a message with data "update" to each of them (to trigger a page reload),
then close the connection. Finally, empty the list since all connections are
closing anyway and clients will re-connect from the re-loaded page.
"""
function update_and_close_viewers!(wss::Vector{HTTP.WebSockets.WebSocket})
    foreach(wss) do wsi
        try
            write(wsi, "update")
            close(wsi)
        catch
        end
    end
    empty!(wss)
    return nothing
end


"""
    file_changed_callback(f_path::AbstractString)

Function reacting to the change of the file at `f_path`. Is set as callback for the file watcher.
"""
function file_changed_callback(f_path::AbstractString)
    VERBOSE[] && println("ℹ [LiveUpdater]: Reacting to change in file '$f_path'...")
    if endswith(f_path, ".html")
        # if html file, update viewers of this file only
        update_and_close_viewers!(WS_VIEWERS[f_path])
    else
        # otherwise (e.g. modification to a CSS file), update all viewers
        foreach(update_and_close_viewers!, values(WS_VIEWERS))
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
    if !isempty(CONTENT_DIR[])
        fs_path = joinpath(CONTENT_DIR[], fs_path)
    end
    # if no file is specified, try to append `index.html` and see
    endswith(req_path, "/") && (fs_path = joinpath(fs_path, "index.html"))
    # either the result is a valid file path in which case it's returned otherwise ""
    return ifelse(isfile(fs_path), fs_path, "")
end


"""
    serve_file(fw, req::HTTP.Request)

Handler function for serving files. This takes a file watcher, to which files to be watched can be
added, and a request (e.g. a path entered in a tab of the browser), and converts it to the
appropriate file system path. If the path corresponds to a HTML file, it will inject the reloading
`<script>` (see file `client.html`) at the end of its body, i.e. directly before the `</body>` tag.
All files served are added to the file watcher, which is responsible to check whether they're
already watched or not. Finally the file is served via a 200 (successful) response. If the file
does not exist, a response with status 404 and an according message is sent.
"""
function serve_file(fw, req::HTTP.Request)
    fs_path = get_fs_path(req.target)
    # in case the path was not resolved, return a 404
    isempty(fs_path) && return HTTP.Response(404, "404: file not found. The most likely reason " *
                                    "is that the URL you entered has a mistake in it or that " *
                                    "the requested page has been deleted or renamed. Check " *
                                    "also that the server is still running.")

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
    ws_upgrade(http::HTTP.Stream)

Upgrade the HTTP request in the stream to a websocket.
"""
function ws_upgrade(http::HTTP.Stream)
    # adapted from HTTP.WebSockets.upgrade; note that here the upgrade will always
    # have  the right format as it always triggered by after a Response
    HTTP.setstatus(http, 101)
    HTTP.setheader(http, "Upgrade" => "websocket")
    HTTP.setheader(http, "Connection" => "Upgrade")
    key = HTTP.header(http, "Sec-WebSocket-Key")
    HTTP.setheader(http, "Sec-WebSocket-Accept" => HTTP.WebSockets.accept_hash(key))
    HTTP.startwrite(http)

    io = http.stream
    return HTTP.WebSockets.WebSocket(io; server=true)
end


"""
    ws_tracker(ws::HTTP.WebSockets.WebSocket, target::AbstractString)

Adds the websocket connection to the viewers in the global dictionary `WS_VIEWERS` to the entry
corresponding to the targeted file.
"""
function ws_tracker(ws::HTTP.WebSockets.WebSocket, target::AbstractString)
    # add to list of html files being "watched"
    # NOTE: this file always exists because the query is generated just after serving it
    fs_path = get_fs_path(target)

    # if the file is already being viewed, add ws to it (e.g. several tabs)
    # otherwise add to dict
    if fs_path ∈ keys(WS_VIEWERS)
        push!(WS_VIEWERS[fs_path], ws)
    else
        WS_VIEWERS[fs_path] = [ws]
    end

    try
        # NOTE: browsers will drop idle websocket connections so this effectively
        # forces the websocket to stay open until it's closed by LiveServer (and
        # not by the browser) upon writing a `update` message on the websocket.
        # See update_and_close_viewers
        while isopen(ws.io)
            sleep(0.1)
        end
    catch err
        # NOTE: there may be several sources of errors caused by the precise moment
        # at which the user presses CTRL+C and after what events. In an ideal world
        # we would check that none of these errors have another source but for now
        # we make the assumption it's always the case (note that it can cause other
        # errors than InterruptException, for instance it can cause errors due to
        # stream not being available etc but these all have the same source).
        # - We therefore do not propagate the error but merely store the information that
        # there was a forcible interruption of the websocket so that the interruption
        # can be guaranteed to be propagated.
        WS_INTERRUPT[] = true
    end
    return nothing
end


"""
    serve(filewatcher; port=8000, dir="", verbose=false, coreloopfun=(c,fw)->nothing)

Main function to start a server at `http://localhost:port` and render what is in the current
directory. (See also [`example`](@ref) for an example folder).

* `filewatcher` is a file watcher implementing the API described for [`SimpleWatcher`](@ref) (which also is the default) and messaging the viewers (via WebSockets) upon detecting file changes.
* `port` is an integer between 8000 (default) and 9000.
* `dir` specifies where to launch the server if not the current working directory.
* `verbose` is a boolean switch to make the server print information about file changes and connections.
* `coreloopfun` specifies a function which can be run every 0.1 second while the liveserver is going; it takes two arguments: the cycle counter and the filewatcher. By default the coreloop does nothing.

# Example

```julia
LiveServer.example()
serve(port=8080, dir="example", verbose=true)
```

If you open a browser to `http://localhost:8080/`, you should see the `index.html` page from the
`example` folder being rendered. If you change the file, the browser will automatically reload the
page and show the changes.
"""
function serve(fw::FileWatcher=SimpleWatcher(file_changed_callback);
               port::Int=8000, dir::AbstractString="", verbose::Bool=false,
               coreloopfun::Function=(c,fw)->nothing)

    8000 ≤ port ≤ 9000 || throw(ArgumentError("The port must be between 8000 and 9000."))
    setverbose(verbose)

    if !isempty(dir)
        isdir(dir) || throw(ArgumentError("The specified dir '$dir' is not recognised."))
        CONTENT_DIR[] = dir
    end

    start(fw)

    # make request handler
    req_handler = HTTP.RequestHandlerFunction(req -> serve_file(fw, req))

    server = Sockets.listen(port)
    println("✓ LiveServer listening on http://localhost:$port/ ...\n  (use CTRL+C to shut down)")
    @async HTTP.listen(Sockets.localhost, port, server=server, readtimeout=0) do http::HTTP.Stream
        if HTTP.WebSockets.is_upgrade(http.message)
            # upgrade to websocket
            ws = ws_upgrade(http)
            # add to list of viewers and keep open until written to
            ws_tracker(ws, http.message.target)
        else
            # handle HTTP request
            HTTP.handle(req_handler, http)
        end
    end

    # wait until user interrupts the LiveServer (using CTRL+C).
    try
        counter = 1
        while true
            if WS_INTERRUPT.x || fw.status == :interrupted
                # rethrow the interruption (which may have happened during
                # the websocket handling or during the file watching)
                throw(InterruptException())
            end
            # do the auxiliary function if there is one (by default this does nothing)
            coreloopfun(counter, fw)
            # update the cycle counter and sleep (yields to other threads)
            counter += 1
            sleep(0.1)
        end
    catch err
        if !isa(err, InterruptException)
            throw(err)
        end
    finally
        # cleanup: close everything that might still be alive
        VERBOSE[] && println("\n⋮ shutting down LiveServer")
        # stop the filewatcher
        stop(fw)
        # close any remaining websockets
        for wss ∈ values(WS_VIEWERS), wsi ∈ wss
            close(wsi.io)
        end
        # empty the dictionary of viewers
        empty!(WS_VIEWERS)
        # shut down the server
        close(server)
        VERBOSE[] && println("\n✓ LiveServer shut down.")
        # reset environment variables
        CONTENT_DIR[] = ""
        WS_INTERRUPT[] = false
    end
    return nothing
end
