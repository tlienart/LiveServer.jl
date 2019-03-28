**WORK IN PROGRESS, MANY FLAWS AND BUGS STILL NEED TO BE FIXED**

# Live Server for Julia

This is a simple development server written in Julia, based on [HTTP.jl](https://github.com/JuliaWeb/HTTP.jl). It has live-reload capability, i.e. when changing files, every browser (tab) currently displaying a corresponding page is automatically updated. This updating is triggered via WebSockets and therefore only works with browsers supporting this feature (and also insecure `ws://` connections to `localhost`).

## Installation
TBD.

## Usage
In a Julia session:
```julia
using LiveServer # exports serve()
cd("path/to/page/root/folder") # e.g. the example folder in this repo
serve()
```
Then open <http://localhost:8000> in a browser. Changing a HTML (e.g. `index.html`) triggers a reload in all browsers currently disiplaying this file. Changes on any other files currently trigger a reload in all connected browsers. That is, the live server does not sniff which JS/CSS/picture/... files are used in which HTML files.
