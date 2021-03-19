using QXRun
using Documenter

makedocs(;
    modules=[QXRun],
    authors="QuantEx team",
    repo="https://github.com/JuliaQX/QXRun.jl/blob/{commit}{path}#L{line}",
    sitename="QXRun.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaQX.github.io/QXRun.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
	"LICENSE" => "license.md"
    ],
)

deploydocs(;
    repo="github.com/JuliaQX/QXRun.jl",
)
