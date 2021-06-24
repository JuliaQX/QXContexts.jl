using Statistics
include("quick_create.jl")

function main(args)
    num = parse(Int, args[1])

    for i in 0:num
        @info("Create context for $i")
        ctx = create_ctx(i, use_gpu=true)
        @info("Context created, warmup")
        warmup = CUDA.@elapsed ctx()
        @info("Warmup completed in $(warmup), collect profile")
        CUDA.@profile NVTX.@range "Run Iteration" begin ctx() end
        @info("Profile complete for $i")
    end
end


main(ARGS)
