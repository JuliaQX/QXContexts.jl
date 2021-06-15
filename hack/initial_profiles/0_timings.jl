using BenchmarkTools
using CUDA

using QXContexts

function main(args)
    file_path  = @__DIR__
    dsl_file   = joinpath(dirname(dirname(file_path)), "examples/ghz/ghz_5.qx")
    input_file = joinpath(dirname(dirname(file_path)), "examples/ghz/ghz_5.jld2")

    cg, _ = parse_dsl_files(dsl_file, input_file)
 
    # get time on cpu
    ctx_cpu = QXContext{Array{ComplexF32}}(cg)
    set_open_bonds!(ctx_cpu)
    t = @elapsed ctx_cpu() # run to ensure all is precompiled
    @info "CPU warmup ran in $t" 
    b = @benchmark $(ctx_cpu)() # benchmark run
    @show b

    # get time on gpu
    ctx_gpu = QXContext{CuArray{ComplexF32}}(cg)
    set_open_bonds!(ctx_gpu)
    t = @elapsed CUDA.@sync begin ctx_gpu() end # run to ensure all is precompiled
    @info "GPU warmup ran in $t" 
    b = @benchmark CUDA.@sync $(ctx_gpu)() # benchmark run
    @show b
end

main(ARGS)
