using Statistics
include("quick_create.jl")

function main(args)
    num = parse(Int, args[1])
    output = args[2]
    n = 10

    open(output, "w") do io
        write(io, "case, warmup, cpu_time, allocated\n")
        for i in 0:num
            @info("Create context for $i")
            ctx = create_ctx(i, use_gpu=false)
            @info("Context created, warmup")
            warmup = @elapsed ctx()
            @info("Warmup completed in $(warmup), collect timings")
            ts = Float64[]
            for j in 1:n
                t = @elapsed ctx()
                push!(ts, t)
            end
            t = median(ts)
            @info("Rand $n iterations, median time: $(t)")
            allocs = @allocated ctx()
            @info("Allocations $allocs")
            write(io, "$(i), $(warmup), $(t), $(allocs)\n")
        end
    end

end


main(ARGS)
