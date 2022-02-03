module SimulationTests

using Test
using QXContexts

@testset "Uniform Simulation tests" begin
    test_path = dirname(@__DIR__)
    dsl_file = joinpath(test_path, "examples/ghz/ghz_5.qx")
    param_file = joinpath(test_path, "examples/ghz/ghz_5_uniform.yml")

    # Test if correct context is created and jobs are assigned to it.
    cg, _ = parse_dsl_files(dsl_file)
    simctx = SimulationContext(param_file, cg)
    @test typeof(simctx) == QXContexts.UniformSim
    contraction_jobs = [job for job in simctx]
    @test length(contraction_jobs) == 40

    # Test if jobs are balanced across ranks.
    rank = 1; comm_size = 4
    simctx = SimulationContext(param_file, cg, rank, comm_size)
    contraction_jobs = collect(simctx)
    @test length(contraction_jobs) == 10

    # Test scheduling of jobs.
    jobs_queue, amps_queue = start_queues(simctx)
    queued_jobs = [take!(jobs_queue) for _ = 1:10]
    @test queued_jobs == contraction_jobs

    # Test collecting amplitudes
    for i = 1:5
        put!(amps_queue, ([0, 1], 1.0))
        put!(amps_queue, ([0, 0], 1.0))
    end
    results = simctx(amps_queue)
    @test results[[0, 1]] == 5.0 + 0.0im
    @test results[[0, 0]] == 5.0 + 0.0im

    # Test saving results
    results = [(true, true) => 1.0, (true, false) => 1.0+1.0im]
    mktempdir() do path
        save_results(simctx, results)
        @test isfile("results.txt")
    end
end

end