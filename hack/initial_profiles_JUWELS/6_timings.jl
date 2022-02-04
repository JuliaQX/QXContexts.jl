using BenchmarkTools
using CUDA
using Statistics

using QXContexts

function main(args)
    file_path  = @__DIR__
    dsl_file   = joinpath(dirname(dirname(file_path)), "examples/rqc/rqc_7_7_32.qx")
    input_file = joinpath(dirname(dirname(file_path)), "examples/rqc/rqc_7_7_32.jld2")

    cg, _ = parse_dsl_files(dsl_file, input_file)

    # get time on cpu
    ctx_cpu = QXContext{Array{ComplexF32}}(cg)
    set_open_bonds!(ctx_cpu)
    set_slice_vals!(ctx_cpu, Int[1, 1, 1, 1])
    t = @elapsed ctx_cpu() # run to ensure all is precompiled
    @info "CPU warmup ran in $t"
    b = @benchmark $(ctx_cpu)() # benchmark run
    @info "CPU benchmark time"
    @show b

    # get time on gpu
    ctx_gpu = QXContext{CuArray{ComplexF32}}(cg)
    set_open_bonds!(ctx_gpu)
    set_slice_vals!(ctx_gpu, Int[1, 1, 1, 1])
    t = @elapsed CUDA.@sync begin ctx_gpu() end # run to ensure all is precompiled
    @info "GPU warmup ran in $t"
    #b = @benchmark CUDA.@sync begin $(ctx_gpu)() end # benchmark run
    CUDA.@time ctx_gpu()
    #@info "GPU benchmark time"
    #@show median(ts)
    ts = []
    for i in 1:5
        t = CUDA.@elapsed ctx_gpu()
        @info "GPU run $i in $t"
        flush(stdout)
        push!(ts, t)
        sleep(1)
    end
    @info "GPU times: $(ts)"
    @info "Mean time: $(mean(ts))"
    flush(stdout)
    nothing
end

main(ARGS)
