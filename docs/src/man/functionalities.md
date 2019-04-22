# Main functions

The two main functions exported by the package are
* [`serve`](@ref) and
* [`servedocs`](@ref),

they are discussed in some details here.

## `serve`

The exported [`serve`](@ref) function is the main function of the package.
The basic usage is

```julia-repl
julia> cd("directory/of/website")
julia> serve()
✓ LiveServer listening on http://localhost:8000/ ...
  (use CTRL+C to shut down)
```

which will make the content of the folder available to be viewed in a browser.

You can specify the port that the server should listen to (default is `8000`) as well as the directory to serve (if not the current one) as keyword arguments.
There is also a `verbose` keyword-argument if you want to see messages being displayed on file changes and
connections.

More interestingly, you can optionally specify the `filewatcher` (the only
regular argument) which allows to define what will trigger the messages to the client and ultimately cause the active browser tabs to reload.
By default, it is file modifications that will trigger page reloads but you may want to write your own file watcher to perform additional actions upon file changes or trigger browser reload differently.

Finally, you can specify a function `coreloopfun` which is called continuously while the server is running.
There may be circumstances where adjusting `coreloopfun` helps to complement the tuning of a `FileWatcher`.

See the section on [Extending LiveServer](@ref) for more informations.

## `servedocs`

The exported [`servedocs`](@ref) function is a convenient function derived from `serve`.
The main purpose is to allow Julia package developpers to live-preview their documentation while working on it by coupling `Documenter.jl` and `LiveServer.jl`.

Let's assume the structure of your package looks like

```
.
├── LICENSE.md
├── Manifest.toml
├── Project.toml
├── README.md
├── docs
│   ├── Project.toml
│   ├── build
│   ├── make.jl
│   └── src
│       └── index.md
├── src
│   └── MyPackage.jl
└── test
    └── runtests.jl

```

The standard way of running `Documenter.jl` is to run `make.jl`, wait for completion and then use a standard browser or maybe some third party tool to see the output.

With `servedocs` however, you can edit the `.md` files in your `docs/src` and see the changes being applied directly in your browser which makes writing documentation faster and easier.
To launch it, navigate to `YourPackage.jl/` and simply

```julia-repl
julia> using YourPackage, LiveServer
julia> servedocs()
```

This will execute `make.jl` (a pass of `Documenter.jl`) before live serving the resulting `docs/build` folder with `LiveServer.jl`.
Upon modifying a `.md` file (e.g. updating `docs/src/index.md`), the `make.jl` will be applied and the corresponding changes propagated to active tabs (e.g. a tab watching `http://localhost:8000/index.html`)

!!! note

    The first pass of `Documenter.jl` takes a few seconds to complete, but subsequent passes are quite fast so that the workflow with `Documenter.jl`+`LiveServer.jl` is pretty quick.

    The first pass collects all information in the code (i.e. docstrings), while
    subsequent passes only consider changes in the markdown (`.md`) files. This
    restriction is necessary to achieve a fast update behavior.
