@testset "AbstractSimContext Interface defaults tests" begin
    struct IncompleteContext <: QXContexts.AbstractSimContext end
    ctx = IncompleteContext()

    # Dummy data.
    i = 1; results = nothing; root = comm = 1; output_file = ""; amps_queue = nothing

    @test_throws ErrorException Base.length(ctx)
    @test_throws ErrorException start_queues(ctx)
    @test_throws ErrorException QXContexts.get_bitstring!(ctx, i)
    @test_throws ErrorException QXContexts.get_slice(ctx, i)
    @test_throws ErrorException QXContexts.get_contraction_job(ctx, i)
    @test_throws ErrorException (ctx)(amps_queue)
end

@testset "Amplitude Simulation tests" begin
    test_path = dirname(@__DIR__)
    dsl_file = joinpath(test_path, "examples/ghz/ghz_5.qx")
    cg, _ = parse_dsl_files(dsl_file)

    # Test if correct context is created for list simulation.
    param_file = joinpath(test_path, "examples/ghz/ghz_5.yml")
    params = parse_parameters(param_file)
    num_amps = params[:params][:num_amps]
    simctx = SimulationContext(param_file, cg)
    @test typeof(simctx) == QXContexts.AmplitudeSim
    contraction_jobs = [job for job in simctx]
    @test length(contraction_jobs) == 4 * num_amps

    # Test if correct context is created for uniform simulation.
    param_file = joinpath(test_path, "examples/ghz/ghz_5_uniform.yml")
    params = parse_parameters(param_file)
    num_amps = params[:params][:num_amps]
    simctx = SimulationContext(param_file, cg)
    @test typeof(simctx) == QXContexts.AmplitudeSim
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
    results = Dict((true, true) => 1.0, (true, false) => 1.0+1.0im)
    mktempdir() do path
        save_results(simctx, results; output_dir = path)
        @test isfile(path * "/results.txt")
    end
end

@testset "Rejection Simulation tests" begin
    test_path = dirname(@__DIR__)
    dsl_file = joinpath(test_path, "examples/ghz/ghz_5.qx")
    cg, _ = parse_dsl_files(dsl_file)

    # Test if correct context is created for rejection simulation.
    param_file = joinpath(test_path, "examples/ghz/ghz_5_rejection.yml")
    params = parse_parameters(param_file)
    num_samples = params[:params][:num_samples]
    simctx = SimulationContext(param_file, cg)
    @test typeof(simctx) == QXContexts.RejectionSim

    # Test if generated bitstring sequence is reproducible.
    bitstring_batch = [QXContexts.get_bitstring!(simctx, i) for i in 1:10]
    bigger_bitstring_batch = [QXContexts.get_bitstring!(simctx, i) for i in 1:20]
    @test bitstring_batch == bigger_bitstring_batch[1:10]

    # Test creating and populating AmplitudeChannel.
    bitstring = [true, true]; slices = simctx.slices
    amps_queue = RemoteChannel(()->QXContexts.AmplitudeChannel{ComplexF32}(length(slices), 7))
    amp_channel = Distributed.lookup_ref(Distributed.remoteref_id(amps_queue)).c
    for n in 1:simctx.num_samples
        for slice in slices put!(amps_queue, bitstring, slice, ComplexF32(0.0)) end
        for slice in slices put!(amps_queue, bitstring, slice, ComplexF32(1.0)) end
    end
    @test length(amp_channel.amps) == 2 * simctx.num_samples
    @test bitstring in amp_channel.bitstrings

    # Test rejection algorithm.
    amplitudes, counts = simctx(amps_queue)
    @test amplitudes[bitstring] == 0
    @test counts[bitstring] == simctx.num_samples

    # Test the amps queue is now empty.
    @test all(0 .== values(amp_channel.queue))
    @test all(0 .== amp_channel.amps)
    @test all(nothing .== amp_channel.bitstrings)

    # Test saving results
    amplitudes = Dict((true, true) => 1.0, (true, false) => 1.0 + 1.0im)
    counts = Dict((true, true) => 1, (true, false) => 2)
    mktempdir() do path
        save_results(simctx, (amplitudes, counts); output_dir = path)
        @test isfile(path * "/amps_results.txt")
        @test isfile(path * "/counts_results.txt")
    end
end