# LiveServer.jl - Documentation

LiveServer is a simple and lightweight development web-server written in Julia, based on [HTTP.jl](https://github.com/JuliaWeb/HTTP.jl).
It has live-reload capability, i.e. when changing files, every browser (tab) currently displaying a corresponding page is automatically refreshed.

LiveServer is inspired from Python's [`http.server`](https://docs.python.org/3/library/http.server.html) and Node's [`browsersync`](https://www.browsersync.io/).

## Installation

The package is currently un-registered.
In Julia ≥ 1.0, you can add it using the Package Manager writing

```
(v1.2) pkg> add https://github.com/asprionj/LiveServer.jl
```

## Usage

The main function `LiveServer` exports is `serve` which starts listening to the current folder and makes its content available to a browser.
The following code creates an example directory and serves it:

```julia
julia> using LiveServer
julia> LiveServer.example() # creates an "example/" folder with some files
julia> cd("example")
julia> serve() # starts the local server & the file watching
✓ LiveServer listening on http://localhost:8000...
  (use CTRL+C to shut down)
```

Open a Browser and go to `http://localhost:8000` to see the content being rendered; try modifying files (such as `index.html`) to see the changes being rendered immediately in the browser.
