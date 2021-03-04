"""
    servedocs_callback!(docwatcher, filepath, path2makejl, literate, foldername)

Custom callback used in [`servedocs`](@ref) triggered when the file corresponding to `filepath`
is changed. If that file is `docs/make.jl`, the callback will check whether any new files have
been added in the `docs/src` folder and add them to the watched files, it will also remove any
file that may have been deleted or renamed.
Otherwise, if the modified file is in `docs/src` or is `docs/make.jl`, a pass of Documenter is
triggered to regenerate the documents, subsequently the LiveServer will render the produced pages
in `docs/build`.
`foldername` can be set other than "docs" if needed.
`buildfoldername` can be set other than "build" if needed.
"""
function servedocs_callback!(dw::SimpleWatcher, fp::AbstractString, makejl::AbstractString,
                             literate::String="", skip_dirs::Vector{String}=String[],
                             foldername::String="docs", buildfoldername="build")
    # ignore things happening in build (generated files etc)
    startswith(fp, joinpath(foldername, buildfoldername)) && return nothing
    if !isempty(skip_dirs)
        for dir in skip_dirs
            startswith(fp, dir) && return nothing
        end
    end
    # if the file that was changed is the `make.jl` file, assume that maybe new files are # referenced and so refresh the vector of watched files as a result.
    if fp == makejl
        # it's easier to start from scratch (takes negligible time)
        empty!(dw.watchedfiles)
        scan_docs!(dw, literate, foldername)
    end
    fext = splitext(fp)[2]
    P1 = fext ∈ (".md", ".jl", ".css")
    # the second condition is for CSS files, we want to track it but not the output
    # if we track the output then there's an infinite loop being triggered (see docstring)
    if P1
        Main.include(makejl)
        file_changed_callback(fp)
    end
    return nothing
end


"""
    scan_docs!(dw::SimpleWatcher, literate="", foldername="docs")

Scans the `docs/` folder in order to recover the path to all files that have to be watched and add
those files to `dw.watchedfiles`. The function returns the path to `docs/make.jl`. A list of
folders and file paths can also be given for files that should be watched in addition to the
content of `docs/src`. `foldername` can be changed if it's different than docs.
"""
function scan_docs!(dw::SimpleWatcher, literate::String="", foldername::String="docs")
    src = joinpath(foldername, "src")
    if !(isdir(foldername) && isdir(src))
        @error "I didn't find a $foldername/ or $foldername/src/ folder."
    end
    makejl = joinpath(foldername, "make.jl")
    push!(dw.watchedfiles, WatchedFile(makejl))
    if isdir(foldername)
        # add all files in `docs/src` to watched files
        for (root, _, files) ∈ walkdir(joinpath(foldername, "src")), file ∈ files
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
            path = replace(spath[1], Regex("^$literate") => joinpath(foldername, "src"))
            k = findfirst(e -> splitext(e.path) == (path, ".md"), dw.watchedfiles)
            k === nothing || push!(remove, k)
        end
    end
    deleteat!(dw.watchedfiles, remove)
    return makejl
end


"""
    servedocs(; verbose=false, literate="", doc_env=false, foldername="docs")

Can be used when developing a package to run the `docs/make.jl` file from Documenter.jl and
then serve the `docs/build` folder with LiveServer.jl. This function assumes you are in the
directory `[MyPackage].jl` with a subfolder `docs`.

* `verbose=false` is a boolean switch to make the server print information about file changes and
connections.
* `literate=""` is the path to the folder containing the literate scripts, if left empty, it will be
assumed that they are in `docs/src`.
* `doc_env=false` is a boolean switch to make the server start by activating the doc environment or not (i.e. the `Project.toml` in `docs/`).
* `skip_dir=""` is a subpath of `docs/` where modifications should not trigger the generation of the docs, this is useful for instance if you're using Weave and Weave generates some files in `docs/src/examples` in which case you should give `skip_dir=joinpath("docs","src","examples")`.
* `skip_dirs=[]` same as `skip_dir`  but for a vector of such dirs. Takes precedence over `skip_dir`.
* `foldername="docs"` specify the name of the content folder if different than "docs".
* `buildfoldername="build"` specify the name of the build folder if different than "build".
* `host="127.0.0.1"` where the server will start.
* `port` is an integer between 8000 (default) and 9000.
* `launch_browser=false` specifies whether to launch the ambient browser at the localhost URL or not.
"""
function servedocs(; verbose::Bool=false, literate::String="",
                     doc_env::Bool=false, skip_dir::String="",
                     skip_dirs::Vector{String}=String[],
                     foldername::String="docs",
                     buildfoldername::String="build",
                     host::String="127.0.0.1", port::Int=8000,
                     launch_browser::Bool = false)
    # Custom file watcher: it's the standard `SimpleWatcher` but with a custom callback.
    docwatcher = SimpleWatcher()

    if isempty(skip_dirs) && !isempty(skip_dir)
        skip_dirs = [skip_dir]
    end

    set_callback!(docwatcher,
                  fp->servedocs_callback!(docwatcher, fp, makejl, literate, skip_dirs, foldername, buildfoldername))

    # Retrieve files to watch
    makejl = scan_docs!(docwatcher, literate, foldername)

    if doc_env
        Pkg.activate("$foldername/Project.toml")
    end
    # trigger a first pass of Documenter (& possibly Literate)
    Main.include(abspath(makejl))

    # note the `docs/build` exists here given that if we're here it means the documenter
    # pass did not error and therefore that a docs/build has been generated.
    serve(docwatcher, host=host, port=port, dir=joinpath(foldername, buildfoldername), verbose=verbose, launch_browser=launch_browser)
    if doc_env
        Pkg.activate()
    end
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

#
# Generate example repo for servedocs
#

const INDEX_MD = raw"""
    # Test
    A link to the [other page](/man/pg1/)
    """
const PG1_JL  = raw"""
    # # Test literate
    # We can include some code like so:
    f(x) = x^5
    f(5)
    """
const MAKE_JL = raw"""
    using Documenter, Literate
    src = joinpath(@__DIR__, "src")
    lit = joinpath(@__DIR__, "literate")
    for (root, _, files) ∈ walkdir(lit), file ∈ files
        splitext(file)[2] == ".jl" || continue
        ipath = joinpath(root, file)
        opath = splitdir(replace(ipath, lit=>src))[1]
        Literate.markdown(ipath, opath)
    end
    makedocs(
        sitename = "testlit",
        pages = ["Home" => "index.md",
                 "Other page" => "man/pg1.md"]
        )
    """

"""
servedocs_literate_example(dir="servedocs_literate_example")

Generates a folder with the right structure for servedocs+literate example.
You can then `cd` to that folder and use servedocs:

```
julia> using LiveServer
julia> LiveServer.servedocs_literate_example()
julia> cd("servedocs_literate_example")
julia> servedocs(literate=joinpath("docs","literate"))
```
"""
function servedocs_literate_example(dirname="servedocs_literate_example")
    isdir(dirname) && rm(dirname, recursive=true)
    mkdir(dirname)
    # folder structure
    src  = joinpath(dirname, "src")
    mkdir(src)
    write(joinpath(src, "$dirname.jl"), "module $dirname\n foo()=1\n end")
    docs = joinpath(dirname, "docs")
    mkdir(docs)
    src = joinpath(docs, "src")
    lit = joinpath(docs, "literate")
    man = joinpath(lit, "man")
    mkdir(src)
    mkdir(lit)
    mkdir(man)
    write(joinpath(src, "index.md"), INDEX_MD)
    write(joinpath(man, "pg1.jl"), PG1_JL)
    write(joinpath(docs, "make.jl"), MAKE_JL)
    return
end
