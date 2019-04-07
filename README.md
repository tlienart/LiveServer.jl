**WORK IN PROGRESS, MANY FLAWS AND BUGS STILL NEED TO BE FIXED**

# Live Server for Julia

| Status (Linux/Mac) | Status (Win) | Coverage | Docs |
| :----: | :----: | :----: | :----: |
| [![Build Status](https://travis-ci.org/asprionj/LiveServer.jl.svg?branch=master)](https://travis-ci.org/asprionj/LiveServer.jl) | [![AppVeyor](https://ci.appveyor.com/api/projects/status/github/asprionj/LiveServer.jl?branch=master&svg=true)](https://ci.appveyor.com/project/asprionj/LiveServer-jl) | [![codecov.io](http://codecov.io/github/asprionj/LiveServer.jl/coverage.svg?branch=master)](http://codecov.io/github/asprionj/LiveServer.jl?branch=master) | [![dev-doc](https://img.shields.io/badge/docs-dev-blue.svg)](https://asprionj.github.io/LiveServer.jl/dev/)

This is a simple and lightweight development server written in Julia, based on [HTTP.jl](https://github.com/JuliaWeb/HTTP.jl).
It has live-reload capability, i.e. when changing files, every browser (tab) currently displaying a corresponding page is automatically refreshed.
This updating is triggered via WebSockets and therefore only works with browsers supporting this feature (and also insecure `ws://` connections to `localhost`).

This package can be compared to python's [`http.server`](https://docs.python.org/3/library/http.server.html) (but with live reload) or node's [`browsersync`](https://www.browsersync.io/) (but much simpler).

## Installation

The package is currently unregistered.
To install it in Julia ≥ 1.0, use the package manager with

```julia-repl
] add https://github.com/asprionj/LiveServer.jl
```

## Usage

The (only) function `LiveServer` exports is `serve` which starts listening to the current folder and makes its content available to a browser.
In a Julia session:

```julia
using LiveServer # exports serve()
cd("path/to/website/folder") # e.g. the example folder in this repo
serve()
```
Then open `http://localhost:8000` in a browser.
Changing a HTML file (e.g. `index.html`) triggers a reload in all browsers currently displaying this file.
Changes on any other files (e.g. `.css`, `.js` etc) currently trigger a reload in all connected viewers.

So, for instance, if you have two tabs opened looking at `index.html` and `pages/page1.html` and
a file `main.css` in the folder is modified, both tabs will be reloaded.
