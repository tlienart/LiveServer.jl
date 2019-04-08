# Main functions

The two main functions exported by `LiveServer` are `serve` and `servedocs`.

## `serve`

The exported [`serve`](@ref) function is the main function of the package.
The basic usage is

```julia
julia> cd("directory/of/website")
julia> serve()
✓ LiveServer listening on http://localhost:8000/ ...
  (use CTRL+C to shut down)
```

which will make the content of the folder available to be viewed in a browser.

You can specify the port that the server should listen to as well as the directory to serve if not the current one (see [`serve`](@ref)).
You can also specify the `filewatcher` which allows to determine what will trigger the messages to the client and ultimately cause the active browser tabs to reload.

By default, it is file modifications that will trigger page reloads but you may want to write your own file watcher to perform additional actions upon file changes or trigger browser reload differently.

See the section on [Extending LiveServer](@ref) for more informations.

## `servedocs`

The exported [`servedocs`](@ref) function is a convenient function derived from `serve`.
The main purpose is to allow Julia package developpers to live-preview their docs while working on it by coupling `Documenter.jl` and `LiveServer.jl`.

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

The standard way of running `Documenter.jl` is to run `make.jl`, wait for completion and then maybe use a third party tool to see the output.
With `servedocs`, you can edit the `.md` files in your `docs/src` and see the changes being applied directly in your browser which makes writing documentation easier.

```julia
julia> # we assume here that you are in MyPackage.jl/
julia> servedocs()
```

This will execute `make.jl` (a pass of `Documenter.jl`) before serving the resulting `docs/build` folder.
Upon modifying a `.md` file (e.g. updating `docs/src/index.md`), a pass of `Documenter.jl` will be applied and the corresponding changes propagated to tabs currently watching `http://localhost:8000/index.html`.

**Notes**:
* the first pass of Documenter.jl is relatively slow but subsequent passes are quite fast so that the workflow with `Documenter.jl`+`LiveServer.jl` does not suffer from large delays,
* you can stop the procedure using `CTRL+C`,
* if you add **new** files to the `src/` folder, you will have to stop and restart `servedocs` otherwise the file will not be considered.
