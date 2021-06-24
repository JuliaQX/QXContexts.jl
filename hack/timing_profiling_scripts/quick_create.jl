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

    prefix = joinpath(path, prefix_map[case])
    cg, m = parse_dsl_files([prefix * x for x in [".qx", ".jld2"]]...)
    ctx = if use_gpu
        QXContext{CuArray{ComplexF32}}(cg)
    else
        QXContext{Array{ComplexF32}}(cg)
    end
    set_open_bonds!(ctx)
    ctx
end
