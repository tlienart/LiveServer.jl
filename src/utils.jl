"""
    servedocs()

Can be used when developping a package to run the `docs/make.jl` file from Documenter.jl and
then serve the `docs/build` folder with LiveServer.jl. This function assumes you are in the
directory `[MyPackage].jl` with a subfolder `docs`.
Note: if you add new pages, you will have to stop and restart `servedocs` after also modifying
your `make.jl` to refer to the new page.
"""
function servedocs()
    makejl = joinpath("docs", "make.jl")

    make_and_callback(fp) = begin
        if fp == makejl || splitext(fp)[2] == ".md"
            include(makejl)
            file_changed_callback(fp)
        end
    end

    docwatcher = SimpleWatcher(make_and_callback)
    push!(docwatcher.watchedfiles, WatchedFile(makejl))

    if isdir("docs") && isfile(makejl)
        # add all *md files in `docs/src` to watched files
        for (root, _, files) ∈ walkdir(joinpath("docs", "src"))
            for file ∈ files
                if splitext(file)[2] == ".md"
                    push!(docwatcher.watchedfiles, WatchedFile(joinpath(root, file)))
                end
            end
        end
        # trigger a first pass
        include(makejl)
        # start continuous watching
        serve(docwatcher, dir=joinpath("docs", "build"))
    else
        @warn "No docs folder found"
    end
    return nothing
end

#
# Miscellaneous utils
#

"""
    verbose(b)

Set the verbosity of LiveServer to either true (showing messages upon events) or false (default).
"""
verbose(b::Bool) = (VERBOSE.x = b)

"""
    example()

Simple function to copy an example website folder to the current working directory that can be
watched by the LiveServer to get an idea of how things work.

### Example

```julia
LiveServer.example()
cd("example")
serve()
```
"""
function example(; basedir="")
    isempty(basedir) && (basedir = pwd())
    cp(joinpath(dirname(dirname(pathof(LiveServer))), "example"), joinpath(basedir, "example"))
end
