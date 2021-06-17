using BenchmarkTools
using CUDA

using QXContexts

function main(args)
    file_path  = @__DIR__
    dsl_file   = joinpath(dirname(dirname(file_path)), "examples/rqc/rqc_6_6_24.qx")
    input_file = joinpath(dirname(dirname(file_path)), "examples/rqc/rqc_6_6_24.jld2")

    cg, _ = parse_dsl_files(dsl_file, input_file)
 
    # get time on gpu
    ctx_gpu = QXContext{CuArray{ComplexF32}}(cg)
    set_open_bonds!(ctx_gpu)
    t = @elapsed CUDA.@sync begin ctx_gpu() end # run to ensure all is precompiled
    @info "GPU warmup ran in $t" 
    CUDA.@profile CUDA.@sync begin ctx_gpu() end
    nothing
end

main(ARGS)
