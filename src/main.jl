# Print a typical cli program help message
function print_help()
    name = basename(@__FILE__)
    io = stdout
    printstyled(io, "NAME\n", bold=true)
    println(io, "       LiveServer.main - run a webserver")
    println(io)
    printstyled(io, "SYNOPSIS\n", bold=true)
    println(io, "       julia -m LiveServer [-h <host>] [-p <port>] [-v] [--help] <directory>")
    println(io)
    printstyled(io, "DESCRIPTION\n", bold=true)
    println(io, """       `LiveServer.main` (typically invoked as `julia -m LiveServer`)
                          starts a web server serving the contents of the specified
                          filesystem directory using the LiveServer.jl Julia package.
                   """)
    printstyled(io, "OPTIONS\n", bold=true)
    println(io, "       <directory>")
    println(io, "           Path to the root directory of the server (default: pwd)")
    println(io, "       -h <host>")
    println(io, "           Specify the host (default: 127.0.0.1)")
    println(io, "       -p <port>")
    println(io, "           Specify the port (default: 8000)")
    println(io, "       -v")
    println(io, "           Enable verbose output")
    println(io, "       --help")
    println(io, "           Show this message")
    return
end

function (@main)(ARGS)
    # Argument defaults
    port::Int = 8000
    host::String = "127.0.0.1"
    verbose::Bool = false
    dir::String = pwd()
    # Argument parsing
    see_help = " See the output of `--help` for usage details."
    while length(ARGS) > 0
        x = popfirst!(ARGS)
        if x == "-p"
            # Parse the port
            if length(ARGS) == 0
                printstyled(stderr, "ERROR: "; bold=true, color=:red)
                println(stderr, "A port number is required after the `-p` flag.", see_help)
                return 1
            end
            pstr = popfirst!(ARGS)
            p = tryparse(Int, pstr)
            if p === nothing
                printstyled(stderr, "ERROR: "; bold=true, color=:red)
                println(stderr, "Could not parse port number from input `$(pstr)`.", see_help)
                return 1
            end
            port = p
        elseif x == "-h"
            # Parse the host
            if length(ARGS) == 0
                printstyled(stderr, "ERROR: "; bold=true, color=:red)
                println(stderr, "A host is required after the `-h` flag.", see_help)
                return 1
            end
            host = popfirst!(ARGS)
        elseif x == "-v"
            # Parse the verbose option
            verbose = true
        elseif x == "--help"
            # Print help and return (even if other arguments are present)
            print_help()
            return 0
        elseif length(ARGS) == 0 && isdir(abspath(x))
            # If ARGS is empty and the argument is a directory this is the root directory
            dir = abspath(x)
        else
            # Unknown argument
            printstyled(stderr, "ERROR: "; bold=true, color=:red)
            println(stderr, "Argument `$x` is not a supported flag or filesystem directory.", see_help)
            return 1
        end
    end
    # Start the server
    LiveServer.serve(; host, port, dir, verbose)
    return 0
end
