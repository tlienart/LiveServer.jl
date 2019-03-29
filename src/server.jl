"""
    update_viewers!(websocket_list)

Send WebSocket message to all viewers (websockets) in the list `wss` to check if they respond,
delete them from the list otherwise. Note that writing
"""
function update_viewers!(wss::Vector{HTTP.WebSockets.WebSocket})
    # TODO: nicer way of checking availability of WebSocket
    # (instead of just trying to send message and failing...?)
    closed_inds = []
    for (i, wsi) ∈ enumerate(wss)
        try
            write(wsi, "update")
        catch e
            push!(closed_inds, i)
        end
    end
    deleteat!(wss, closed_inds)
end

"""
    file_changed_callback(filepath, ev)

Callback that gets fired once a change to a file `filepath` is detected (FileEvent `ev`).
"""
function file_changed_callback(filepath::AbstractString, ev::FileWatching.FileEvent)
    # only do something if file was changed ONLY
    if ev.changed && !ev.renamed && !ev.timedout
        VERBOSE.x && println("File '$filepath' changed...")
        if lowercase(splitext(filepath)[2]) ∈ (".html", ".htm")
            # if html file, update viewers of this file only
            println("HTML file, only updating corresponding viewers...")
            update_viewers!(WS_HTML_FILES[filepath])
        else
            # otherwise, update all viewers
            println("Infra file, updating all viewers...")
            for wss ∈ values(WS_HTML_FILES)
                update_viewers!(wss)
            end
        end
    end
end

# instantiate file watcher
const LS_FILE_WATCHER = FileWatcher(file_changed_callback)

"""
    get_file(filepath)

Get filesystem path to requested file, or `nothing` if the file does not exist.
"""
function get_file(filepath::AbstractString)
    # TODO make sure ok on windows
    (filepath[1] == '/') && (filepath = "."*filepath)

    if filepath[end] == '/'
        # have to check for index.htm(l)
        phtm = joinpath(filepath, "index.html")
        isfile(phtm) && return phtm
        phtml = phtm * "l"
        isfile(phtml) && return phtml
        return nothing
    else
        return isfile(filepath) ? filepath : nothing
    end
end

"""
    file_server(req)

Handler function for serving files
"""
function file_server(req::HTTP.Request)
    fs_filepath = get_file(req.target)

    if fs_filepath == nothing
        return HTTP.Response(404, "404 not found")
    else
        file_content = read(fs_filepath) # raw Vector{UInt8}

        # if html, add the browser-sync script to it
        if lowercase(splitext(fs_filepath)[2]) ∈ (".htm", ".html")
            file_string = String(file_content)
            end_of_body_match = match(r"</body>", file_string)

            if end_of_body_match == nothing
                # TODO: what to do ∈ this case? (no </body> found)
                # just add to end of file...?
                file_string *= BROWSER_RELOAD_SCRIPT
            else
                end_of_body = prevind(file_string, end_of_body_match.offset)
                io = IOBuffer()
                write(io, file_string[1:end_of_body])
                write(io, BROWSER_RELOAD_SCRIPT)
                write(io, file_string[nextind(file_string, end_of_body):end])
                file_string = String(take!(io))
            end
            file_content = Vector{UInt8}(file_string)
        end
        # add file to watcher
        println("Adding file '$fs_filepath' to watcher...")
        start_watching(LS_FILE_WATCHER, fs_filepath)
        return HTTP.Response(200, file_content)
    end
end

"""
    ws_tracker(http)

The WebSocket tracker -- upgrades HTTP request to WS.
"""
function ws_tracker(http::HTTP.Stream)
    println("WebSocket request from $(http.message.target)...")

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

    # if the file is already being watched, add ws to it; otherwise add to dict
    if filepath ∈ keys(WS_HTML_FILES)
        push!(WS_HTML_FILES[filepath], ws)
    else
        WS_HTML_FILES[filepath] = [ws]
    end

    for (file, wss) ∈ WS_HTML_FILES
        # remove all ws from list that is closing or already closed
        filter!(wsi -> wsi.io.c.io.status ∉ (Base.StatusClosed, Base.StatusClosing), wss)

        # for now, just print out the ws's active for this file
        println("WebSocket connections for file '$file':")
        for wsi ∈ wss
            @show wsi.io
        end
    end
end

"""
    serve(; ipaddr, port, verbose)

Main function to start a server at `http://ipaddr:port` and render what is in the current folder.

* `ipaddr` is either a string representing a valid IP address (e.g.: `"127.0.0.1"`) or an `IPAddr`
object (e.g.: `ip"127.0.0.1"`). You can also write `"localhost"` (default).
* `port` is an integer between 8000 (default) and 9000.
* `verbose` is a boolean indicating whether to display informations in Julia about the connections
or not (default).

### Example

```julia
cd(joinpath(pathof(LiveServer), "example"))
serve()
```

If you open a browser to `localhost:8000`, you should see the `index.html` page from the `example`
folder being rendered.
"""
function serve(; ipaddr::Union{String, IPAddr}="localhost", port::Int=8000, verbose::Bool=false)
    if isa(ipaddr, String)
        if ipaddr == "localhost"
            ipaddr = ip"0.0.0.0"
        else
            ipaddr = parse(IPAddr, ipaddr)
        end
    end
    8000 ≤ port ≤ 9000 || throw(ArgumentError("The port must be between 8000 and 9000."))
    # make the verbosity level available to the whole program
    VERBOSE.x = verbose

    # start a server
    inetaddr = Sockets.InetAddr(ipaddr, port)
    server = Sockets.listen(inetaddr)

    println("✓ LiveServer listening on $ipaddr:$port...")

    @async HTTP.listen(ipaddr, port; server=server) do http::HTTP.Stream
        if HTTP.WebSockets.is_upgrade(http.message)
            ws_tracker(http)
        else
            HTTP.handle(HTTP.RequestHandlerFunction(file_server), http)
        end
    end

    try while true
        sleep(0.1)
        end
    catch err
        if isa(err, InterruptException)
            close(server)
            stop_tasks(LS_FILE_WATCHER)
        println("\n✓ LiveServer shut down.")
        else
            throw(err)
        end
    end
    return nothing
end
