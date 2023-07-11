# LiveServer + Literate

(_Thanks to [Fredrik Ekre](https://github.com/fredrikekre) and [Benoit Pasquier](https://github.com/briochemc) for their input; a lot of this section is drawn from an early prototype suggested by Fredrik._)

You've likely already seen how LiveServer could be used along with Documenter to have live updating documentation (see [`servedocs`](/man/functionalities/#servedocs-1) if not).

It is also easy to use LiveServer with both Documenter and [Literate.jl](https://github.com/fredrikekre/Literate.jl), a package for literate programming written by Fredrik Ekre that can convert julia script files into markdown.
This can be particularly convenient for documentation pages with a lot of code examples.

There are mainly two steps 

1. have the `make.jl` file process the literate files to go from `.jl` to `.md` files,
2. call `servedocs` with appropriate keywords.

The function `LiveServer.servedocs_literate_example` generates a directory which has the right structure that you can copy for your package.
To experiment, do:

```julia-repl
julia> using LiveServer
julia> LiveServer.servedocs_literate_example("test_dir")
julia> cd("test_dir")
julia> servedocs(literate_dir=joinpath("docs", "literate"))
```

if you then navigate to `localhost:8000` you should end up with

![](../../assets/testlit.png)

if you modify `test_dir/docs/literate/man/pg1.jl` for instance writing `f(4)` it will be applied directly:

![](../../assets/testlit2.png)


In the explanations below we assume you have defined

* `LITERATE_INPUT` the directory where the literate files are,
* `LITERATE_OUTPUT` the directory where the generated markdown files will be.


## Having the make file call Literate

Here's a basic `make.jl` file which loops over the files in `LITERATE_INPUT` to generate files
in `LITERATE_OUTPUT` 

```julia
using Documenter, Literate

LITERATE_INPUT = ...
LITERATE_OUTPUT = ...

for (root, _, files) ∈ walkdir(LITERATE_INPUT), file ∈ files
    # ignore non julia files
    splitext(file)[2] == ".jl" || continue
    # full path to a literate script
    ipath = joinpath(root, file)
    # generated output path
    opath = splitdir(replace(ipath, LITERATE_INPUT=>LITERATE_OUTPUT))[1]
    # generate the markdown file calling Literate
    Literate.markdown(ipath, opath)
end

makedocs(
    ...
    )
```

## Calling servedocs with the right arguments

`LiveServer.servedocs` needs to know two things to work with literate scripts properly:

* where the scripts are
* where the generated files will be

it can make assumptions for some basic cases but, in general, you'll have to provide both.

Doing so improperly may lead to an infinite loop where:
* the first `make.jl` call generates markdown files with Literate
* these generated markdown files themselves trigger `make.jl`
* (infinite loop)

To avoid this, you must generally call `servedocs` as follows when working with literate files:

```
servedocs(
    literate_dir = LITERATE_INPUT
    skip_dir = LITERATE_OUTPUT
)
```

where

* `literate_dir` is the parent directory of the literate scripts, and
* `skip_dir` is the parent directory where the generated markdown files are placed.

**Special cases**:

* if the literate scripts are located in `docs/src` you can just specify `literate_dir=""`,
* if the literate scripts are generated with in `docs/src` with the exact same relative path, you
do not need to specify `skip_dir`.


### Example 1 <!-- checked 10/7/2023 | 1.2.1 -->

```
docs
└── src
    ├── literate_script.jl
    └── literate_script.md
```

in this case we can call 

```julia
servedocs(literate="")
```

since

1. the literate scripts are under `docs/src`
2. the generated markdown files have exactly the same relative path.


### Example 2 <!-- checked 10/7/2023 | 1.2.1 -->

```
docs
├── literate
│   └── literate_script.jl
└── src
    └── literate_script.md
```

in this case we can call 

```julia
servedocs(literate=joinpath("docs", "literate"))
```

since

1. the literate scripts are under a dedicated folder,
2. the generated markdown files have exactly the same relative path.

### Example 3 <!-- checked 10/7/2023 | 1.2.1 -->

```
foo
├── literate
│   └── literate_script.jl
docs
└── src
    └── generated
        └── literate_script.md
```

in this case we can call 

```julia
servedocs(literate=joinpath("foo", "literate"), skip_dir=joinpath())
```

since

1. the literate scripts are under a dedicated folder,
2. the generated markdown files do not have exactly the same relative path.

