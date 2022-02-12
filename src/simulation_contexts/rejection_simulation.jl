#=
Here we define the rejection simulation implementation of the AbstractSimContext type.

In a rejection sampling simulation, uniformly random bitstrings are generated and
accepted as a sample from the circuits output distribution with a probability
depending on the bitstrings probability amplitude. After a specified number of samples
are collected, the computed amplitudes and the accepted counts of each bitstring are 
saved as the simulation's output.
=#
include("amplitude_channel.jl")

"""Data structure for rejection sampling simulation context."""
mutable struct RejectionSim <: AbstractSimContext
    num_qubits::Integer
    num_samples::Integer
    samples_collected::Integer
    slices::CartesianIndices
    num_slices::Integer

    M::Real
    fix_M::Bool

    seed::Integer
    rng::MersenneTwister
    rng_checkpoint::MersenneTwister
    next_bitstring::Integer
end


"""Rejection simulation context constructor"""
function RejectionSim(slice_params,
                    rank,
                    comm_size;
                    num_qubits::Integer,
                    num_samples::Integer,
                    M::Real=0.0,
                    fix_M::Bool=false,
                    seed::Integer=42,
                    kwargs...)
    num_samples = num_samples ÷ comm_size + (rank < (num_samples % comm_size))
    M = fix_M ? M : 1/2^num_qubits
    M == 0.0 && error("M should be larger than zero for rejection sampling.")

    # Get the slices of the tensor network.
    dims = map(x -> slice_params[Symbol("v$(x)")], 1:length(slice_params))
    slices = CartesianIndices(Tuple(dims))

    # Initialise the random number generator.
    seed = seed + rank
    rng = MersenneTwister(seed)
    rng_checkpoint = copy(rng)

    RejectionSim(num_qubits, num_samples, 0, slices, length(slices), M, fix_M, seed, rng, rng_checkpoint, 1)
end

"""Run the rejection sampling algorithm using the stream of ampltiudes in the given queue."""
function (ctx::RejectionSim)(amps_queue::RemoteChannel)
    amplitudes = Dict{Vector{Bool}, ComplexF32}()
    counts = Dict{Vector{Bool}, Int64}()
    rng = MersenneTwister(ctx.seed)
    N = 2^ctx.num_qubits
    M = ctx.M
    @debug "Starting rejection sampling with M=$M"

    while ctx.samples_collected < ctx.num_samples
        bitstring, amp = take!(amps_queue)
        @debug "Next candidate is bitstring=$(prod(string.(Int.(bitstring)))) with amp=$amp"
        !haskey(amplitudes, bitstring) && (amplitudes[bitstring] = amp)

        Np = N * abs(amp)^2
        ctx.fix_M || (M = max(Np, M))
        if rand(rng) < Np / M
            ctx.samples_collected += 1
            counts[bitstring] = get(counts, bitstring, 0) + 1
            @debug "Accepted! The number of samples is now $(ctx.samples_collected)"
        end
    end

    amplitudes, counts
end

"""Initialise and return the queues used for the simulation."""
function start_queues(ctx::RejectionSim)
    jobs_queue = RemoteChannel(()->Channel{Tuple{Vector{Bool}, CartesianIndex}}(32))
    amps_queue = RemoteChannel(()->AmplitudeChannel{ComplexF32}(ctx.num_slices, 32))
    errormonitor(@async schedule_contraction_jobs(ctx, jobs_queue))
    jobs_queue, amps_queue
end

function collect_results(ctx::RejectionSim, results::Tuple{Dict, Dict}, root, comm)
    amps, counts = results
    all_amps = collect_results(ctx, amps, root, comm)
    all_counts = collect_results(ctx, counts, root, comm)
    all_amps, all_counts
end

function save_results(ctx::RejectionSim, results::Tuple{Dict, Dict}; output_dir::String="", output_file::String="")
    amps, counts = results
    output_file = joinpath(output_dir, output_file)
    output_dir = dirname(output_file)
    output_file = basename(output_file)
    output_file = output_file == "" ? "results.txt" : output_file
    save_results(ctx, amps; output_dir = output_dir, output_file = "amps_" * output_file)
    save_results(ctx, counts; output_dir = output_dir, output_file = "counts_" * output_file)
end

function get_bitstring!(ctx::RejectionSim, i::Integer)
    if i < ctx.next_bitstring
        ctx.rng_checkpoint = MersenneTwister(ctx.seed)
        ctx.next_bitstring = 1
    end
    copy!(ctx.rng, ctx.rng_checkpoint)
    if i > ctx.next_bitstring
        [rand(ctx.rng, Bool, ctx.num_qubits) for _ in ctx.next_bitstring:i-1]
        ctx.rng_checkpoint = copy(ctx.rng)
        ctx.next_bitstring = i
    end
    rand(ctx.rng, Bool, ctx.num_qubits)
end

Base.length(ctx::RejectionSim) = Inf64 # TODO: This probably isn't the best thing to do, should probably raise an error here.
get_slice(ctx::RejectionSim, slice_i::Integer) = ctx.slices[slice_i]
get_contraction_job(ctx::RejectionSim, state::Integer) = (state ÷ ctx.num_slices + 1, state % ctx.num_slices + 1)