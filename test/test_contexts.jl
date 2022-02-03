module TestContexts

using Test
using QXContexts

include("utils.jl")

@testset "Test Contraction contexts" begin
    test_path = dirname(@__DIR__)
    dsl_file = joinpath(test_path, "examples/ghz/ghz_5.qx")
    data_file = joinpath(test_path, "examples/ghz/ghz_5.jld2")

    cg, _ = parse_dsl_files(dsl_file, data_file)
    conctx = QXContext(cg)

    # Test contraction
    bitstring = Bool[0, 0, 0, 0, 0]
    slice = CartesianIndex((1, 1))
    amp = conctx(bitstring, slice)

    # Test job fetching and storing results
    jobs_queue = RemoteChannel(()->Channel{Tuple{Vector{Bool}, CartesianIndex}}(32))
    amps_queue = RemoteChannel(()->Channel{Tuple{Vector{Bool}, ComplexF32}}(32))
    for _ = 1:7 put!(jobs_queue, (bitstring, slice)) end
    t = @async conctx(jobs_queue, amps_queue)
    results = [take!(amps_queue) for _ = 1:7]
    @test !isready(amps_queue)

    # Test contraction task finishes when job queue closed.
    @test !istaskdone(t)
    close(jobs_queue)
    @test istaskdone(t)

    # contract while summing over view parameters
    # @test compute_amplitude!(ctx, "0") ≈ output_0
    # @test compute_amplitude!(ctx, "1") ≈ output_1
    # @test compute_amplitude!(ctx, "1", max_slices=0) ≈ output_1
end

end