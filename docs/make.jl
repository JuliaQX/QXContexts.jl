using QXContexts
using Documenter

makedocs(;
    modules=[QXContexts],
    authors="QuantEx team",
    repo="https://github.com/JuliaQX/QXContexts.jl/blob/{commit}{path}#L{line}",
    sitename="QXContexts.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaQX.github.io/QXContexts.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
	"LICENSE" => "license.md"
    ],
)

deploydocs(;
    repo="github.com/JuliaQX/QXContexts.jl",
)
