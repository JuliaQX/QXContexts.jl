ghz_results = Dict{Vector{Bool}, ComplexF32}(
    [1, 1, 0, 0, 1] => 0 + 0im,
    [1, 0, 0, 0, 0] => 0 + 0im,
    [0, 0, 0, 1, 1] => 0 + 0im,
    [0, 0, 0, 0, 0] => 1/sqrt(2) + 0im,
    [1, 1, 0, 0, 0] => 0 + 0im,
    [1, 0, 0, 1, 0] => 0 + 0im,
    [1, 0, 1, 1, 1] => 0 + 0im,
    [0, 1, 0, 1, 0] => 0 + 0im,
    [0, 1, 1, 0, 1] => 0 + 0im,
    [1, 1, 1, 1, 1] => 1/sqrt(2) + 0im,
)

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
    amps_queue = RemoteChannel(()->Channel{Tuple{Vector{Bool}, Array{ComplexF32, 0}}}(32))
    for _ = 1:7 put!(jobs_queue, (bitstring, slice)) end
    t = @async conctx(jobs_queue, amps_queue)
    results = [take!(amps_queue) for _ = 1:7]
    @test !isready(amps_queue)

    # Test contraction task finishes when job queue closed.
    @test !istaskdone(t)
    close(jobs_queue)
    sleep(1)
    @test istaskdone(t)

    # Test if computed amplitudes are correct.
    for bitstring in keys(ghz_results)
        amp = 0
        for slice in CartesianIndices((2, 2))
            amp += conctx(bitstring, slice)[]
        end
        @test amp ≈ ghz_results[bitstring]
    end
end