using Test
using QXContexts

@testset "Uniform Simulation tests" begin
    test_path = dirname(@__DIR__)
    dsl_file = joinpath(test_path, "examples/ghz/ghz_5.qx")
    param_file = joinpath(test_path, "examples/ghz/ghz_5_uniform.yml")
    params = parse_parameters(param_file)
    num_amps = params[:params][:num_amps]

    # Test if correct context is created and jobs are assigned to it.
    cg, _ = parse_dsl_files(dsl_file)
    simctx = SimulationContext(param_file, cg)
    @test typeof(simctx) == QXContexts.UniformSim
    contraction_jobs = [job for job in simctx]
    @test length(contraction_jobs) == 4 * num_amps

    # Test if jobs are balanced across ranks.
    rank = 1; comm_size = 4
    simctx = SimulationContext(param_file, cg, rank, comm_size)
    contraction_jobs = collect(simctx)
    @test length(contraction_jobs) == num_amps

    # Test scheduling of jobs.
    jobs_queue, amps_queue = start_queues(simctx)
    queued_jobs = [take!(jobs_queue) for _ = 1:length(simctx)]
    @test queued_jobs == contraction_jobs

    # Test collecting amplitudes
    amp = fill(ComplexF32(1.0),())
    for i = 1:length(simctx)/2
        put!(amps_queue, ([0, 1], amp))
        put!(amps_queue, ([0, 0], amp))
    end
    results = simctx(amps_queue)
    @test results[[0, 1]] == ComplexF32(length(simctx)/2)
    @test results[[0, 0]] == ComplexF32(length(simctx)/2)

    # Test saving results
    results = [(true, true) => 1.0, (true, false) => 1.0+1.0im]
    mktempdir() do path
        save_results(simctx, results)
        @test isfile("results.txt")
    end
end