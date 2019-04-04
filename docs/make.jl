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
        # "Manual" => [
        #     "Quick start"          => "man/quickstart.md",
        #     ],
        "Library" => [
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
