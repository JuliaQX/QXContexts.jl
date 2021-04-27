using QXContexts

root = dirname(dirname(@__DIR__))

prefixes = [joinpath(root, "examples/ghz/ghz_5"),
            joinpath(root, "examples/rqc/rqc_4_4_24"),
            joinpath(root, "examples/rqc/rqc_6_6_24")]

mktempdir() do path
    for prefix in prefixes
        execute(prefix * ".qx", prefix * ".yml", prefix * ".jld2", joinpath(path, "out.jld2"))
    end
end
