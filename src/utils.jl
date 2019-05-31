"""
    servedocs_callback!(docwatcher, filepath, path2makejl, literate)

Custom callback used in [`servedocs`](@ref) triggered when the file corresponding to `filepath`
is changed. If that file is `docs/make.jl`, the callback will check whether any new files have
been added in the `docs/src` folder and add them to the watched files, it will also remove any
file that may have been deleted or renamed.
Otherwise, if the modified file is in `docs/src` or is `docs/make.jl`, a pass of Documenter is
triggered to regenerate the documents, subsequently the LiveServer will render the produced pages
in `docs/build`.
"""
function servedocs_callback!(dw::SimpleWatcher, fp::AbstractString, makejl::AbstractString,
                             literate::String="")
    # if the file that was changed is the `make.jl` file, assume that maybe new files are # referenced and so refresh the vector of watched files as a result.
    if fp == makejl
        # it's easier to start from scratch (takes negligible time)
        empty!(dw.watchedfiles)
        scan_docs!(dw, literate)
    end
    fext = splitext(fp)[2]
    P1 = fext ∈ (".md", ".jl")
    # the second condition is for CSS files, we want to track it but not the output
    # if we track the output then there's an infinite loop being triggered (see docstring)
    if P1 || (fext == ".css" && !occursin(joinpath("docs", "build", "assets"), fp))
        Main.include(makejl)
        file_changed_callback(fp)
    end
    return nothing
end


"""
    scan_docs!(dw::SimpleWatcher, literate="")

Scans the `docs/` folder in order to recover the path to all files that have to be watched and add
those files to `dw.watchedfiles`. The function returns the path to `docs/make.jl`. A list of
folders and file paths can also be given for files that should be watched in addition to the
content of `docs/src`.
"""
function scan_docs!(dw::SimpleWatcher, literate::String="")
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
    if !isempty(literate)
        isdir(literate) || @error "I didn't find the provided literate folder $literate."
        for (root, _, files) ∈ walkdir(literate), file ∈ files
            push!(dw.watchedfiles, WatchedFile(joinpath(root, file)))
        end
    end

    # When using literate.jl, we should only watch the source file otherwise we would double
    # trigger: first when the script.jl is modified then again when the script.md is created
    # which would cause an infinite loop if both `script.jl` and `script.md` are watched.
    # So here we remove from the watchlist all files.md that have a files.jl with the same path.
    remove = Int[]
    if isempty(literate)
        # assumption is that the scripts are in `docs/src/...` and that the generated markdown
        # goes in exactly the same spot so for instance:
        # docs
        # └── src
        #     ├── index.jl
        #     └── index.md
        for wf ∈ dw.watchedfiles
            spath = splitext(wf.path)
            spath[2] == ".jl" || continue
            k = findfirst(e -> splitext(e.path) == (spath[1], ".md"), dw.watchedfiles)
            k === nothing || push!(remove, k)
        end
    else
        # assumption is that the scripts are in `literate/` and that the generated markdown goes
        # in `docs/src` with the same relative paths so for instance:
        # docs
        # ├── lit
        # │   └── index.jl
        # └── src
        #     └── index.md
        for (root, _, files) ∈ walkdir(literate), file ∈ files
            spath = splitext(joinpath(root, file))
            spath[2] == ".jl" || continue
            path = replace(spath[1], Regex("^$literate") => joinpath("docs", "src"))
            k = findfirst(e -> splitext(e.path) == (path, ".md"), dw.watchedfiles)
            k === nothing || push!(remove, k)
        end
    end
    deleteat!(dw.watchedfiles, remove)
    return makejl
end


"""
    servedocs(; verbose=false, literate="")

Can be used when developing a package to run the `docs/make.jl` file from Documenter.jl and
then serve the `docs/build` folder with LiveServer.jl. This function assumes you are in the
directory `[MyPackage].jl` with a subfolder `docs`.

* `verbose` is a boolean switch to make the server print information about file changes and
connections.
* `literate` is the path to the folder containing the literate scripts, if left empty, it will be
assumed that they are in `docs/src`.
"""
function servedocs(; verbose::Bool=false, literate::String="")
    # Custom file watcher: it's the standard `SimpleWatcher` but with a custom callback.
    docwatcher = SimpleWatcher()
    set_callback!(docwatcher, fp->servedocs_callback!(docwatcher, fp, makejl, literate))

    # Retrieve files to watch
    makejl = scan_docs!(docwatcher, literate)

    # trigger a first pass of Documenter (& possibly Literate)
    Main.include(makejl)

    # note the `docs/build` exists here given that if we're here it means the documenter
    # pass did not error and therefore that a docs/build has been generated.
    serve(docwatcher, dir=joinpath("docs", "build"), verbose=verbose)
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
