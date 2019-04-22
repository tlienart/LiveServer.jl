#=
This is a patch for issue #405 (https://github.com/JuliaWeb/HTTP.jl/issues/405) which allows
the proper closing of @async tasks that are launched by the listen loop of HTTP. Without this
patch these tasks may live on which may cause bugs further downstream.
This patch is "not ideal"; a better solution would be to cleanly keep track of all tasks. The
better solution will likely be implemented in the future but in the mean time this patch fixes the
bug and is simple. It will be removed when the bug is fixed proper upstream.

This concerns only `src/Servers.jl` and specifically `listenloop`; the difference can be seen in
https://github.com/JuliaWeb/HTTP.jl/pull/406
=#

using HTTP.IOExtras
using HTTP.Streams
using HTTP.Messages
#using HTTP.Parsers
using HTTP.ConnectionPool

import HTTP.Servers.listenloop

function listenloop(f::Function, server, tcpisvalid, connection_count,
                    reuse_limit, readtimeout, verbose)
    count = 1
    while isopen(server)
        try
            io = accept(server)

            if !tcpisvalid(io)
                verbose && @info "Accept-Reject:  $io"
                close(io)
                continue
            end
            connection_count[] += 1
            conn = Connection(io)
            conn.host, conn.port = server.hostname, server.hostport
            let io=io, count=count
                @async try
                    verbose && @info "Accept ($count):  $conn"
                    handle_connection(f, conn, reuse_limit, readtimeout, server)
                    verbose && @info "Closed ($count):  $conn"
                catch e
                    if e isa Base.IOError && e.code == -54
                        verbose && @warn "connection reset by peer (ECONNRESET)"
                    else
                        @error exception=(e, stacktrace(catch_backtrace()))
                    end
                finally
                    connection_count[] -= 1
                    close(io)
                    verbose && @info "Closed ($count):  $conn"
                end
            end
        catch e
            if e isa InterruptException
                @warn "Interrupted: listen($server)"
                close(server)
                break
            else
                rethrow(e)
            end
        end
        count += 1
    end
    return
end

function handle_connection(f, c::Connection, reuse_limit, readtimeout, server)
    wait_for_timeout = Ref{Bool}(true)
    if readtimeout > 0
        @async check_readtimeout(c, readtimeout, wait_for_timeout)
    end
    try
        count = 0
        while isopen(c)
            if isopen(server)
                handle_transaction(f, Transaction(c), server;
                                   final_transaction=(count == reuse_limit))
                count += 1
            else
                close(c)
            end
        end
    finally
        wait_for_timeout[] = false
    end
    return
end

function handle_transaction(f, t::Transaction, server; final_transaction::Bool=false)
    request = Request()
    http = Stream(request, t)

    try
        startread(http)
    catch e
        if e isa EOFError && isempty(request.method)
            return
        elseif e isa ParseError
            status = e.code == :HEADER_SIZE_EXCEEDS_LIMIT  ? 413 : 400
            write(t, Response(status, body = string(e.code)))
            close(t)
            return
        else
            rethrow(e)
        end
    end

    request.response.status = 200
    if final_transaction || hasheader(request, "Connection", "close")
        setheader(request.response, "Connection" => "close")
    end

    @async try
        if isopen(server)
            f(http)
            closeread(http)
            closewrite(http)
        end
    catch e
        # @error "error handling request" exception=(e, stacktrace(catch_backtrace()))
        if isopen(http) && !iswritable(http)
            http.message.response.status = 500
            startwrite(http)
            write(http, sprint(showerror, e))
        end
        final_transaction = true
    finally
        final_transaction && close(t.c.io)
    end
    return
end
