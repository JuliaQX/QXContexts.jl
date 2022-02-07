#=
Below we define the uniform simulation implementation of the AbstractSimContext type.

In a uniform simulation, probability amplitudes are computed for a predetermined number
of uniformly random bitstrings and saved as the simulation's output. By using direct
sampling methods, these can then be used to generate random bitstrings with a
distribution that approximates (or exactly matches, in the case where all 2^n bitstrings
are used) the output distribution of the quantum circuit.
=#

"""Data structure for uniform simulation implementation"""
mutable struct UniformSim <: AbstractSimContext
    num_qubits::Integer
    num_amps::Integer
    bitstrings::Vector{Vector{Bool}}
    slices::CartesianIndices
    contraction_jobs::Vector{CartesianIndex}
end

"""Contructor for the uniform simulation context"""
function UniformSim(slice_params,
                    rank,
                    comm_size;
                    num_qubits::Integer,
                    num_amps::Integer,
                    seed::Integer=42,
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
    dims = map(x -> slice_params[Symbol("v$(x)")], 1:length(slice_params))
    slices = CartesianIndices(Tuple(dims))
    all_jobs = CartesianIndices((length(slices), num_amps))
    contraction_jobs = get_jobs(all_jobs, rank, comm_size)

    UniformSim(num_qubits, num_amps, collect(bitstrings), slices, contraction_jobs)
end

"""Collect amplitudes from the given queue and store them in a results dictionary."""
function (ctx::UniformSim)(amps_queue::RemoteChannel)
    results = Dict{Vector{Bool}, ComplexF32}()
    for i = 1:length(ctx)
        bitstring, amp = take!(amps_queue)
        results[bitstring] = get(results, bitstring, 0) + amp[]
    end
    results
end

"""Initialise and return the queues used for the simulation."""
function start_queues(ctx::UniformSim)
    jobs_queue = RemoteChannel(()->Channel{Tuple{Vector{Bool}, CartesianIndex}}(32))
    amps_queue = RemoteChannel(()->Channel{Tuple{Vector{Bool}, Array{ComplexF32, 0}}}(32))
    errormonitor(@async schedule_contraction_jobs(ctx, jobs_queue))
    jobs_queue, amps_queue
end

"""Collect all results on the root rank."""
function collect_results(ctx::UniformSim, results, root, comm)
    local_results = [NTuple{ctx.num_qubits, Bool}(k) => v for (k, v) in pairs(results)]
    result_sizes = MPI.Allgather(Int32[length(local_results)], comm)
    recvbuf = MPI.Comm_rank(comm) == root ? MPI.VBuffer(similar(local_results, sum(result_sizes)), result_sizes) : nothing
    all_results = MPI.Gatherv!(local_results, recvbuf, root, comm)

    if all_results !== nothing
        combined_results = Dict{NTuple{ctx.num_qubits, Bool}, ComplexF32}()
        for (bitstring, amp) in all_results
            combined_results[bitstring] = get(combined_results, bitstring, 0) + amp
        end
        return combined_results
    end
    nothing
end

"""Write the given results to a file."""
function save_results(ctx::UniformSim, results, output_file="")
    results === nothing && return
    output_file == "" && (output_file = "results.txt")
    open(output_file, "a") do io
        for (bitstring, amp) in pairs(results)
            bitstring = prod([bit ? "1" : "0" for bit in bitstring])
            println(io, bitstring, " : ", amp)
        end
    end
end

Base.length(ctx::UniformSim) = length(ctx.contraction_jobs)
get_bitstring!(ctx::UniformSim, i::Integer) = ctx.bitstrings[i]
get_slice(ctx::UniformSim, slice_i::Integer) = ctx.slices[slice_i]
get_contraction_job(ctx::UniformSim, state::Integer) = Tuple(ctx.contraction_jobs[state])