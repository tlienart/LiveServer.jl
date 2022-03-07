# Live Server for Julia

[![CI Actions Status](https://github.com/tlienart/LiveServer.jl/workflows/CI/badge.svg)](https://github.com/tlienart/LiveServer.jl/actions)
[![codecov](https://codecov.io/gh/tlienart/LiveServer.jl/branch/master/graph/badge.svg?token=mNry6r2aIn)](https://codecov.io/gh/tlienart/LiveServer.jl)
[![dev-doc](https://img.shields.io/badge/docs-dev-blue.svg)](https://tlienart.github.io/LiveServer.jl/dev/)

This is a simple and lightweight development web-server written in Julia, based on [HTTP.jl](https://github.com/JuliaWeb/HTTP.jl).
It has live-reload capability, i.e. when modifying a file, every browser (tab) currently displaying the corresponding page is automatically refreshed.

LiveServer is inspired from Python's [`http.server`](https://docs.python.org/3/library/http.server.html) and Node's [`browsersync`](https://www.browsersync.io/).

## Installation

To install it in Julia ≥ 1.0, use the package manager with

```julia-repl
pkg> add LiveServer
```

## Usage

The main function `LiveServer` exports is `serve` which starts listening to the current folder and makes its content available to a browser.
The following code creates an example directory and serves it:

```julia
julia> using LiveServer
julia> LiveServer.example() # creates an "example/" folder with some files
julia> cd("example")
julia> serve() # starts the local server & the file watching
✓ LiveServer listening on http://localhost:8000/ ...
  (use CTRL+C to shut down)
```

Open a Browser and go to `http://localhost:8000/` to see the content being rendered; try modifying files (e.g. `index.html`) and watch the changes being rendered immediately in the browser.

In the REPL:
```julia-repl
julia> using LiveServer
julia> serve(host="0.0.0.0", port=8001, dir=".") # starts the remote server & the file watching
✓ LiveServer listening on http://0.0.0.0:8001...
  (use CTRL+C to shut down)
```
In the terminal:
```julia-repl
julia -e 'using LiveServer; serve(host="0.0.0.0", port=8001, dir=".")'  # like as: python -m http.server 8001
```

Open a browser and go to https://localhost:8001/ to see the rendered content of index.html or, if it doesn't exist, the content of the directory.
You can set the port to a custom number.
This is similar to the [`http.server`](https://docs.python.org/3/library/http.server.html) in Python.

### Serve docs

`servedocs` is a convenience function that runs `Documenter` along with `LiveServer` to watch your doc files for any changes and render them in your browser when modifications are detected.  

Assuming you are in `directory/to/YourPackage.jl` and that you have a `docs/` folder as prescribed by [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl), just run:

```julia
julia> using YourPackage, LiveServer
julia> servedocs()
[ Info: SetupBuildDirectory: setting up build directory.
[ Info: ExpandTemplates: expanding markdown templates.
...
└ Deploying: ✘
✓ LiveServer listening on http://localhost:8000/ ...
  (use CTRL+C to shut down)
```

Open a browser and go to `http://localhost:8000/` to see your docs being rendered; try modifying files (e.g. `docs/index.md`) and watch the changes being rendered in the browser.

**Note**: this works with [Literate.jl](https://github.com/fredrikekre/Literate.jl) as well. See [the docs](https://tlienart.github.io/LiveServer.jl/dev/man/ls+lit/).
