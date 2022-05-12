#=
Below we define the amplitude simulation implementation of the AbstractSimContext type.

The AmplitudeSim type defines two simulation modes: uniform and list simulations.

In a uniform simulation, probability amplitudes are computed for a predetermined number
of uniformly random bitstrings and saved as the simulation's output. By using direct
sampling methods, these can then be used to generate random bitstrings with a
distribution that approximates (or exactly matches, in the case where all 2^n bitstrings
are used) the output distribution of the quantum circuit.

A list simulation computes probability amplitudes for a predefined list of bitstrings.
This can be used to verify a set of bitstrings, produced by a physical quantum circuit,
has the correct distribution.
=#

"""Data structure for amplitude simulation context"""
mutable struct AmplitudeSim{T} <: AbstractSimContext
    num_qubits::Integer
    num_amps::Integer
    bitstrings::Vector{Vector{Bool}}
    slices::CartesianIndices
    contraction_jobs::Vector{CartesianIndex}
end

"""Uniform simulation constructor for the amplitude simulation context"""
function UniformSim(slice_params,
                    rank,
                    comm_size;
                    num_qubits::Integer,
                    num_amps::Integer,
                    seed::Integer=42,
                    elt::DataType=ComplexF32,
                    kwargs...)
    # Check the number of requested ampltiudes doesn't exceed 2^num_qubits.
    log2(num_amps) <= num_qubits || error("Too many amplitudes for the number of qubits.")

    # Generate num_amps unique, uniformly random bitstrings.
    rng = MersenneTwister(seed)
    bitstrings = Set{Vector{Bool}}()
    while length(bitstrings) < num_amps
        push!(bitstrings, rand(rng, Bool, num_qubits))
    end

    # Determine the contraction jobs to be assigned to the returned simulation context.
    num_slices = haskey(kwargs, :slices) ? kwargs[:slices] : length(slice_params)
    @assert num_slices <= length(slice_params) "Number of slices must be <= $(length(slice_params))"
    dims = collect(values(slice_params))[1:num_slices]
    slices = CartesianIndices(Tuple(dims))
    all_jobs = CartesianIndices((num_amps, length(slices)))
    contraction_jobs = get_jobs(all_jobs, rank, comm_size)

    AmplitudeSim{elt}(num_qubits, num_amps, collect(bitstrings), slices, contraction_jobs)
end

"""List simulation constructor for the amplitude simulation context"""
function ListSim(slice_params,
                rank,
                comm_size;
                bitstrings::Vector{String}=String[],
                elt::DataType=ComplexF32,
                kwargs...)
    # Check the list of bitstrings is non-empty.
    isempty(bitstrings) && error("No bitstrings to compute amplitudes for.")
    
    # Get the bitstrings to compute amplitudes for.
    num_qubits = length(bitstrings[1])
    num_amps = haskey(kwargs, :num_amps) ? min(kwargs[:num_amps], length(bitstrings)) : length(bitstrings)
    bitstring_list = [[parse(Bool, bit) for bit in bitstring] for bitstring in bitstrings[1:num_amps]]

    # Determine the contraction jobs to be assigned to the returned simulation context.
    num_slices = haskey(kwargs, :slices) ? kwargs[:slices] : length(slice_params)
    @assert num_slices <= length(slice_params) "Number of slices must be <= $(length(slice_params))"
    dims = collect(values(slice_params))[1:num_slices]
    slices = CartesianIndices(Tuple(dims))
    all_jobs = CartesianIndices((num_amps, length(slices)))
    contraction_jobs = get_jobs(all_jobs, rank, comm_size)

    AmplitudeSim{elt}(num_qubits, num_amps, bitstring_list, slices, contraction_jobs)
end

"""Collect amplitudes from the given queue and store them in a results dictionary."""
function (ctx::AmplitudeSim{T})(amps_queue::RemoteChannel) where T <: Number
    results = Dict{Vector{Bool}, T}()
    for i = 1:length(ctx)
        bitstring, slice, amp = take!(amps_queue)
        results[bitstring] = get(results, bitstring, 0) + amp
    end
    results
end

"""Initialise and return the queues used for the simulation."""
function start_queues(ctx::AmplitudeSim{T}) where T <: Number
    jobs_queue = RemoteChannel(() -> Channel{Tuple{Vector{Bool}, CartesianIndex}}(32))
    amps_queue = RemoteChannel(() -> Channel{Tuple{Vector{Bool}, CartesianIndex, T}}(32))
    errormonitor(@async schedule_contraction_jobs(ctx, jobs_queue))
    jobs_queue, amps_queue
end

Base.length(ctx::AmplitudeSim) = length(ctx.contraction_jobs)
get_bitstring!(ctx::AmplitudeSim, i::Integer) = ctx.bitstrings[i]
get_slice(ctx::AmplitudeSim, slice_i::Integer) = ctx.slices[slice_i]
get_contraction_job(ctx::AmplitudeSim, state::Integer) = Tuple(ctx.contraction_jobs[state])
