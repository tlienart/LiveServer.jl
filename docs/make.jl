using Documenter, LiveServer

makedocs(
    modules = [LiveServer],
    format = Documenter.HTML(
        # Use clean URLs, unless built as a "local" build
        prettyurls = !("local" in ARGS)
        ),
    sitename = "LiveServer.jl",
    authors  = "Jonas Asprion, Thibaut Lienart",
    pages    = [
        "Home" => "index.md",
        "Manual" => [
            "Live server"    => "man/server.md",
            "File watching"  => "man/watching.md",
            ],
        "Library" => [
            "Public"    => "lib/public.md",
            "Internals" => "lib/internals.md",
            ],
        ], # end pages
    ##
    ## custom CSS if required
    # assets = ["assets/custom.css"],
)

deploydocs(
    repo = "github.com/asprionj/LiveServer.jl.git"
)
