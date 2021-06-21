using CUDA
using BenchmarkTools
using Test
using OMEinsum

function test1(a, b, c, d)
    e = a .* b
    f = c .* d
    e .* f
end 

function test1ec(a, b, c, d)
    e = EinCode(((1,), (1,)), (1,))(a, b)
    f = EinCode(((1,), (1,)), (1,))(c, d)
    g = EinCode(((1,), (1,)), (1,))(e, f)
    g
end

function test2(d)
    d[:e] = d[:a] .* d[:b]
    d[:f] = d[:c] .* d[:d]
    d[:g] = d[:e] .* d[:f]
    d[:g]
end

function test2ec(d)
    d[:e] = EinCode(((1,), (1,)), (1,))(d[:a], d[:b])
    d[:f] = EinCode(((1,), (1,)), (1,))(d[:c], d[:d])
    d[:g] = EinCode(((1,), (1,)), (1,))(d[:e], d[:f])
    d[:g]
end

function mymult(d, a, b, c)
    d[c] = d[a] .* d[b]
end


function test3(d, plan)
    for p in plan
        mymult(d, p[1], p[2], p[3])
    end
    d[plan[end][3]]
end

function mymultec(d, a, b, c)
    d[c] = EinCode(((1,), (1,)), (1,))(d[a], d[b])
end

function test3ec(d, plan)
    for p in plan
        mymultec(d, p[1], p[2], p[3])
    end
    d[plan[end][3]]
end

function test4(a, b, c, d)
    (a .* b) .* (c .* d)
end 

function test4ec(a, b, c, d)
    EinCode(((1,),(1,)), (1,))(
        EinCode(((1,),(1,)), (1,))(a, b),
        EinCode(((1,),(1,)), (1,))(c, d)
    )
end 


function main(args)
    dim = 10000
    a = CUDA.rand(dim)
    b = CUDA.rand(dim)
    c = CUDA.rand(dim)
    d = CUDA.rand(dim)
    CUDA.synchronize()

    # do all warmups
    CUDA.@sync test1(a, b, c, d)
    CUDA.@sync test1ec(a, b, c, d)
    dict = Dict(:a => a, :b => b, :c => c, :d => d)
    CUDA.@sync g = test2(dict)
    dict = Dict(:a => a, :b => b, :c => c, :d => d)
    CUDA.@sync g = test2ec(dict)
    dict = Dict(:a => a, :b => b, :c => c, :d => d)
    plan = [[:a, :b, :e], [:c, :d, :f], [:e, :f, :g]]
    CUDA.@sync g = test3(dict, plan)
    dict = Dict(:a => a, :b => b, :c => c, :d => d)
    plan = [[:a, :b, :e], [:c, :d, :f], [:e, :f, :g]]
    CUDA.@sync g = test3ec(dict, plan)
    CUDA.@sync test4(a, b, c, d)
    CUDA.@time CUDA.@sync test4ec(a, b, c, d)


    CUDA.@profile begin
        NVTX.@range "Tests" begin
            g1 = NVTX.@range "test 1" begin
                CUDA.@time CUDA.@sync test1(a, b, c, d)
            end
            g1ec = NVTX.@range "test 1 EC" begin
                CUDA.@time CUDA.@sync test1ec(a, b, c, d)
            end

            dict = Dict(:a => a, :b => b, :c => c, :d => d)
            g2 = NVTX.@range "test 2" begin
                CUDA.@time CUDA.@sync test2(dict)
            end
            dict = Dict(:a => a, :b => b, :c => c, :d => d)
            g2ec = NVTX.@range "test 2 EC" begin
                CUDA.@time CUDA.@sync test2ec(dict)
            end

            dict = Dict(:a => a, :b => b, :c => c, :d => d)
            g3 = NVTX.@range "test 3" begin
                CUDA.@time CUDA.@sync test3(dict, plan)
            end
            dict = Dict(:a => a, :b => b, :c => c, :d => d)
            g3ec = NVTX.@range "test 3 EC" begin
                CUDA.@time CUDA.@sync test3ec(dict, plan)
            end

            g4 = NVTX.@range "test 4" begin
                CUDA.@time CUDA.@sync test4(a, b, c, d)
            end
            g4ec = NVTX.@range "test 4 EC" begin
                CUDA.@time CUDA.@sync test4ec(a, b, c, d)
            end
        end
        @test all(g1 .== g1ec)
        @test all(g1 .== g2)
        @test all(g2 .== g2ec)
        @test all(g1 .== g3)
        @test all(g3 .== g3ec)
        @test all(g1 .== g4ec)
        @test all(g4 .== g4ec)
    end

   end

main(ARGS)
