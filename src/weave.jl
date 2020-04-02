"""
    serveweave(file::AbstractString; port=8080, verbose=false, kwargs...)

Track changes to Weave file `file` (usually with a "jmd" extension) and run the
command `weave(kwargs...)`, followed by a browser reload.

Except the the keyword arguments specified above, all other keyword arguments
are passed directly to `weave`. Thus, use `serveweave` exactly as you would
`weave`.

`serveweave` is only meant to substitute for `weave` when the latter is being
used for producing html output.

# Example

```julia
using Weave, Liveserver
serveweave('example.jmd', cache=:user, port=8080)
```
and then point a browser to the url `http://localhost:8080/example.html`.
"""
function serveweave(file::AbstractString;
                    port::Int=8000,
                    verbose::Bool=false,
                    weaveargs...)
    dw = SimpleWatcher(fp->weave_callback!(fp; weaveargs...))
    push!(dw.watchedfiles, WatchedFile(file))
    htmlfile = splitext(file)[1]*".html"
    push!(dw.watchedfiles, WatchedFile(htmlfile))
    serve(dw, verbose=verbose)
    return nothing
end

"""
Run `weave` anytime that `fp`, but only execute the page-reload callback if
Weave's html output changes.
"""
function weave_callback!(fp; kwargs...)
    Weave.weave(fp; kwargs...)
    if endswith(fp, ".html")
        file_changed_callback(fp)
    end
    return nothing
end
