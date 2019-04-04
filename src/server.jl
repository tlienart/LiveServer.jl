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

Function reacting to the change of files. Is set as callback for the
file watcher.
"""
function file_changed_callback(filepath::AbstractString)
    println("ℹ [LiveUpdater]: Reacting to change in file '$filepath'...")
    if lowercase(splitext(filepath)[2]) ∈ (".html", ".htm")
        # if html file, update viewers of this file only
        update_and_close_viewers!(WS_HTML_FILES[filepath])
    else
        # otherwise (e.g. modification to a CSS file), update all viewers
        foreach(update_and_close_viewers!, values(WS_HTML_FILES))
    end
end


"""
    get_file(filepath::AbstractString)

Get filesystem path to requested file, or `nothing` if the file does not exist.
"""
function get_file(filepath::AbstractString)
    # TODO: use HTTP.URI stuff to ensure portability. URI targets always come
    #       with forward slashes, which is OK for Linux-based systems but not
    #       for Windows...
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

        # add this file to the file watcher, send content to client
        watch_file(fw, fs_filepath)
        return HTTP.Response(200, file_content)
    end
end


"""
    ws_tracker(::HTTP.Stream)

The websocket tracker. Upgrades the HTTP request in the stream to a websocket
and adds this connection to the viewers in the global dictionary
`WS_HTML_FILES`.
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
    serve(filewatcher=SimpleWatcher(); ipaddr::Union{String,IPAddr}, port::Int)

Main function to start a server at `http://ipaddr:port` and render what is in the current folder.

* `filewatcher` is a file watcher implementing the API described for [`SimpleWatcher`](@ref)
* `ipaddr` is either a string representing a valid IP address (e.g.: `"127.0.0.1"`) or an `IPAddr`
object (e.g.: `ip"127.0.0.1"`). You can also write `"localhost"` (default).
* `port` is an integer between 8000 (default) and 9000.

### Example

```julia
cd(joinpath(pathof(LiveServer), "example"))
serve()
```

If you open a browser to `localhost:8000`, you should see the `index.html` page from the `example`
folder being rendered. If you change the file, the browser should automatically
reload the page and show the changes.
"""
function serve(filewatcher=SimpleWatcher(); ipaddr::Union{String,IPAddr}="localhost", port::Int=8000)
    # check arguments
    if isa(ipaddr, String)
        if ipaddr == "localhost"
            ipaddr = ip"0.0.0.0"
        else
            ipaddr = parse(IPAddr, ipaddr)
        end
    end
    8000 ≤ port ≤ 9000 || throw(ArgumentError("The port must be between 8000 and 9000."))

    # set the callback and start the file watcher
    set_callback(filewatcher, file_changed_callback)
    start(filewatcher)

    # make request handler
    req_handler = HTTP.RequestHandlerFunction(req -> serve_file(filewatcher, req))

    # start listening
    saddr = "http://"
    if ipaddr == "localhost"
        saddr *= "localhost"
        ipaddr = ip"127.0.0.1"
    else
        saddr *= "$ipaddr"
    end

    server = Sockets.listen(port)
    println("✓ LiveServer listening on $saddr:$port...\n  (use CTRL+C to shut down)")
    @async HTTP.listen(ipaddr, server=server) do http::HTTP.Stream
        if HTTP.WebSockets.is_upgrade(http.message)
            # upgrade to websocket
            ws_tracker(http)
        else
            # directly handle HTTP request
            HTTP.handle(req_handler, http)
        end
    end

    # wait until user issues a CTRL+C command.
    try while true
        sleep(0.1)
        end
    catch err
        if isa(err, InterruptException)
            println("\n⋮ shutting down the live server")

            stop(filewatcher) # stop the file watcher

            # close all websockets
            for wss ∈ values(WS_HTML_FILES)
                foreach(wsi -> close(wsi.io), wss)
            end
            empty!(WS_HTML_FILES)

            close(server) # shut down server
            println("\n✓ LiveServer shut down.")
        else
            throw(err)
        end
    end
    return nothing
end
