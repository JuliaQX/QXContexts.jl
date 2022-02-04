using MPI
using Random
using Distributed
using QXContexts.Param

export SimulationContext, start_queues, collect_results, save_results

abstract type AbstractSimContext end

function schedule_contraction_jobs(ctx::AbstractSimContext, jobs_queue::RemoteChannel)
    for (bitstring, slice) in ctx
        put!(jobs_queue, (bitstring, slice))
    end
end

Base.iterate(ctx::AbstractSimContext) = iterate(ctx, 1)

function Base.iterate(ctx::AbstractSimContext, state::Integer)
    state > length(ctx) && return nothing
    slice_i, bitstring_j = get_contraction_job(ctx, state)
    (get_bitstring!(ctx, bitstring_j), get_slice(ctx, slice_i)), state + 1
end

Base.length(ctx::AbstractSimContext) = error("length is not yet implemented for ", typeof(ctx))
start_queues(ctx::AbstractSimContext) = error("start_queues is not yet implemented for ", typeof(ctx))
get_slices(ctx::AbstractSimContext) = error("get_slices is not yet implemented for ", typeof(ctx))
get_bitstring(ctx::AbstractSimContext) = error("get_bitstring is not yet implemented for ", typeof(ctx))



#===================================================#
# List Simulation
#===================================================#
struct ListSim <: AbstractSimContext end



#===================================================#
# Uniform Simulation
#===================================================#
mutable struct UniformSim <: AbstractSimContext
    num_qubits::Integer
    num_amps::Integer
    bitstrings::Vector{Vector{Bool}}
    slices::CartesianIndices
    contraction_jobs::Vector{CartesianIndex}
end

function UniformSim(slice_params,
                    rank,
                    comm_size;
                    num_qubits::Integer,
                    num_amps::Integer,
                    seed::Integer=42,
                    kwargs...)
    log2(num_amps) <= num_qubits || error("Too many amplitudes for the number of qubits.")

    rng = MersenneTwister(seed)
    bitstrings = Set{Vector{Bool}}()
    while length(bitstrings) < num_amps
        push!(bitstrings, rand(rng, Bool, num_qubits))
    end

    dims = map(x -> slice_params[Symbol("v$(x)")], 1:length(slice_params))
    slices = CartesianIndices(Tuple(dims))

    all_jobs = CartesianIndices((length(slices), num_amps))
    contraction_jobs = get_jobs(all_jobs, rank, comm_size)

    UniformSim(num_qubits, num_amps, collect(bitstrings), slices, contraction_jobs)
end

function start_queues(ctx::UniformSim)
    jobs_queue = RemoteChannel(()->Channel{Tuple{Vector{Bool}, CartesianIndex}}(32))
    amps_queue = RemoteChannel(()->Channel{Tuple{Vector{Bool}, Array{ComplexF32, 0}}}(32))
    errormonitor(@async schedule_contraction_jobs(ctx, jobs_queue))
    jobs_queue, amps_queue
end

get_bitstring!(ctx::UniformSim, i::Integer) = ctx.bitstrings[i]

function (ctx::UniformSim)(amps_queue::RemoteChannel)
    results = Dict{Vector{Bool}, ComplexF32}()
    for i = 1:length(ctx)
        bitstring, amp = take!(amps_queue)
        results[bitstring] = get(results, bitstring, 0) + amp[]
    end
    results
end

function collect_results(ctx::UniformSim, results, root, comm)
    results = [NTuple{ctx.num_qubits, Bool}(k) => v for (k, v) in pairs(results)]
    result_sizes = MPI.Allgather(Int32[length(results)], comm)
    recvbuf = MPI.Comm_rank(comm) == root ? MPI.VBuffer(similar(results, sum(result_sizes)), result_sizes) : nothing
    MPI.Gatherv!(results, recvbuf, root, comm) #TODO: combine slices from different ranks
end

function save_results(ctx::UniformSim, results, output_file="")
    results === nothing && return
    output_file == "" && (output_file = "results.txt")
    open(output_file, "a") do io
        for (bitstring, amp) in results
            bitstring = prod([bit ? "1" : "0" for bit in bitstring])
            println(io, bitstring, " : ", amp)
        end
    end
end

get_slice(ctx::UniformSim, slice_i::Integer) = ctx.slices[slice_i]
get_contraction_job(ctx::UniformSim, state::Integer) = Tuple(ctx.contraction_jobs[state])
Base.length(ctx::UniformSim) = length(ctx.contraction_jobs)

#===================================================#
# Rejection Sampling Simulation
#===================================================#
struct RejectionSim <: AbstractSimContext end

# mutable struct UniformSim <: AbstractSimContext
#     num_qubits::Integer
#     num_amps::Integer
#     seed::Integer
#     rng::MersenneTwister
#     rng_checkpoint::MersenneTwister
#     next_bitstring::Integer

#     slices::CartesianIndices
#     contraction_jobs::Vector{CartesianIndex}
# end

# function get_bitstring!(ctx::RejectionSim, i::Integer)
#     if i < ctx.next_bitstring
#         ctx.rng_checkpoint = MersenneTwister(ctx.seed)
#         ctx.next_bitstring = 1
#     end
#     copy!(ctx.rng, ctx.rng_checkpoint)
#     if i > ctx.next_bitstring
#         [rand(ctx.rng, Bool, ctx.num_qubits) for _ in ctx.next_bitstring:i-1]
#         ctx.rng_checkpoint = copy(ctx.rng)
#         ctx.next_bitstring = i
#     end
#     rand(ctx.rng, Bool, ctx.num_qubits)
# end



#===================================================#
# Convenience Functions
#===================================================#
"""Simulation Context Constructor"""
function SimulationContext(param_file, cg, rank=0, comm_size=1)
    slice_params = params(cg, ViewCommand)
    sim_params = parse_parameters(param_file)
    get_constructor(sim_params[:method])(
                                        slice_params, 
                                        rank, 
                                        comm_size;
                                        sim_params[:params]...
                                        )
end

get_constructor(func_name::String) = getfield(QXContexts, Symbol(func_name*"Sim"))
# rand_bitstring(rng, num_bits) = prod(rand(rng, ["0", "1"], num_bits))

function get_jobs(all_jobs, rank, comm_size)
    num_jobs = length(all_jobs)
    all_jobs[start_stop(num_jobs, rank, comm_size)]
end

function start_stop(num_jobs, rank, size)
    batch_size = num_jobs ÷ size
    trailing = num_jobs % size
    if rank < trailing
        start = rank * (batch_size + 1)
        stop = start + batch_size
    else
        start = rank * batch_size + trailing
        stop = start + batch_size - 1
    end
    return (start + 1):(stop + 1)
end
