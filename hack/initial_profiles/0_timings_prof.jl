using BenchmarkTools
using CUDA

using QXContexts

function main(args)
    file_path  = @__DIR__
    dsl_file   = joinpath(dirname(dirname(file_path)), "examples/ghz/ghz_5.qx")
    input_file = joinpath(dirname(dirname(file_path)), "examples/ghz/ghz_5.jld2")

    cg, _ = parse_dsl_files(dsl_file, input_file)
 
    # get time on gpu
    ctx_gpu = QXContext{CuArray{ComplexF32}}(cg)
    set_open_bonds!(ctx_gpu)
    # run to ensure all is precompiled
    t = NVTX.@range "Warm up" begin @elapsed ctx_gpu() end
    @info "GPU warmup ran in $t" 
    CUDA.@profile NVTX.@range "Run iteration" begin
        ctx_gpu()
    end
    nothing
end

main(ARGS)
