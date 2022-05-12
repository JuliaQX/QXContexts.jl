using QXContexts

include("../../bin/qxsimulate.jl")

root = dirname(dirname(@__DIR__))

prefixes = [joinpath(root, "examples/ghz/ghz_5"),
            joinpath(root, "examples/rqc/rqc_4_4_24"),
            joinpath(root, "examples/rqc/rqc_6_6_24")]

mktempdir() do path
    for prefix in prefixes
        output_fname = joinpath(path, "out.jld2")
        args = ["-d", prefix * ".qx",
                "-p", prefix * ".yml",
                "-o", output_fname,
                "-l", path]
        main(args)
    end
end
