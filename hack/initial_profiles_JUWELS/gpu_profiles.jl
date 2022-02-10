using Statistics
using QXContexts
using CUDA

function create_ctx(case=0 ;use_gpu=true)
    path = dirname(dirname(@__DIR__))
    prefix_map = Dict(0 => "examples/ghz/ghz_5",
                      1 => "examples/rqc/rqc_4_4_24",
                      2 => "examples/rqc/rqc_6_6_24",
                      3 => "examples/rqc/rqc_5_5_32",
                      4 => "examples/rqc/rqc_7_7_24",
                      5 => "examples/rqc/rqc_6_6_32",
                      6 => "examples/rqc/rqc_7_7_32")

    @assert case < 10 "Case must be less than 10"
    prefix = joinpath(path, prefix_map[min(case, 6)])
    cg, m = parse_dsl_files([prefix * x for x in [".qx", ".jld2"]]...)
    ctx = if use_gpu
        QXContext{CuArray{ComplexF32}}(cg)
    else
        QXContext{Array{ComplexF32}}(cg)
    end
    set_open_bonds!(ctx)
    case >= 6 && set_slice_vals!(ctx_cpu, Int[1 for i in 1:4 - (case - 6)])
    ctx
end

function main(args)
    num = parse(Int, args[1])

    for i in 0:num
        @info("Create context for $i")
        ctx = create_ctx(i, use_gpu=true)
        @info("Context created. Warming up")
        warmup = CUDA.@elapsed ctx()
        @info("Warmup completed in $(warmup). Collecting profile")
        CUDA.@profile NVTX.@range "Run Iteration $i" begin ctx() end
        @info("Profile complete for $i")
    end
end


main(ARGS)
