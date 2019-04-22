"""
    servedocs_callback(filepath, watchedfiles, path2makejl)

Custom callback used in [`servedocs`](@ref) triggered when the file corresponding to `filepath`
is changed. If that file is `docs/make.jl`, the callback will check whether any new files have
been added in the `docs/src` folder and add them to the watched files, it will also remove any
file that may have been deleted or renamed.
Otherwise, if the modified file is in `docs/src` or is `docs/make.jl`, a pass of Documenter is
triggered to regenerate the documents, subsequently the LiveServer will render the produced pages
in `docs/build`.
"""
function servedocs_callback(fp::AbstractString, vwf::Vector{WatchedFile}, makejl::AbstractString)
    ismakejl = (fp == makejl)
    # if the file that was changed is the `make.jl` file,
    # assume that maybe new files are referenced and so refresh the
    # vector of watched files as a result.
    if ismakejl
        watchedpaths = (wf.path for wf ∈ vwf)
        for (root, _, files) ∈ walkdir(joinpath("docs", "src")), file ∈ files
            fpath = joinpath(root, file)
            fpath ∈ watchedpaths || push!(vwf, WatchedFile(fpath))
        end
        # check if any file that was watched has died
        deadfiles = Int[]
        for (i, wf) ∈ enumerate(vwf)
            isfile(wf.path) || push!(deadfiles, i)
        end
        deleteat!(vwf, deadfiles)
    end
    # only trigger for changes appearing in `docs/src` otherwise a loop gets triggered
    # changes from docs/src create change in docs/build which trigger a pass which
    # regenerates files in docs/build etc...
    if ismakejl || occursin(joinpath("docs", "src"), fp)
        include(makejl)
        file_changed_callback(fp)
    end
    return nothing
end

"""
    scan_docs!(dw::SimpleWatcher)

Scans the `docs/` folder in order to recover the path to all files that have to be watched and add
those files to `dw.watchedfiles`. The function returns the path to `docs/make.jl`.
"""
function scan_docs!(dw::SimpleWatcher)
    src = joinpath("docs", "src")
    if !(isdir("docs") && isdir(src))
        @error "I didn't find a docs/ or docs/src/ folder."
    end
    makejl = joinpath("docs", "make.jl")
    push!(dw.watchedfiles, WatchedFile(makejl))
    if isdir("docs")
         # add all files in `docs/src` to watched files
         for (root, _, files) ∈ walkdir(joinpath("docs", "src")), file ∈ files
             push!(dw.watchedfiles, WatchedFile(joinpath(root, file)))
         end
    end
    return makejl
end

"""
    servedocs()

Can be used when developping a package to run the `docs/make.jl` file from Documenter.jl and
then serve the `docs/build` folder with LiveServer.jl. This function assumes you are in the
directory `[MyPackage].jl` with a subfolder `docs`.
"""
function servedocs()
    # Custom file watcher: it's the standard `SimpleWatcher` but with a custom callback.
    docwatcher = SimpleWatcher()
    set_callback!(docwatcher, fp->servedocs_callback(fp, docwatcher.watchedfiles, makejl))

    makejl = scan_docs!(docwatcher)

    # trigger a first pass of Documenter
    include(makejl)

    # note the `docs/build` exists here given that if we're here it means the documenter
    # pass did not error and therefore that a docs/build has been generated.
    serve(docwatcher, dir=joinpath("docs", "build"))

    return nothing
end

#
# Miscellaneous utils
#

"""
    setverbose(b)

Set the verbosity of LiveServer to either `true` (showing messages upon events) or `false` (default).
"""
setverbose(b::Bool) = (VERBOSE.x = b)

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
