using QXRunner
using Documenter

makedocs(;
    modules=[QXRunner],
    authors="QuantEx team",
    repo="https://github.com/JuliaQX/QXRunner.jl/blob/{commit}{path}#L{line}",
    sitename="QXRunner.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaQX.github.io/QXRunner.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
	"LICENSE" => "license.md"
    ],
)

deploydocs(;
    repo="github.com/JuliaQX/QXRunner.jl",
)
