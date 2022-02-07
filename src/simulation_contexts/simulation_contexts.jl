#=
Here we define the abstract simulation context type. Concrete implementations of this type are
responsible for effectively distributing contraction jobs amongst worker processes, collecting
probability amplitudes from those worker processes and using them to produce relevant output.

Each concrete subtype in effect defines a unique 'simulation mode' which produces a specific
output. To achieve this, each concrete subtype is expected to implement the interface outlined
below.
=#

using MPI
using Random
using Distributed
using QXContexts.Param
using QXContexts.ComputeGraphs: ComputeGraph

export SimulationContext, start_queues, collect_results, save_results

abstract type AbstractSimContext end

#===================================================#
# Simulation Context Interface
#===================================================#
# TODO: test that these work correctly.
"""Return the number of contraction jobs assigned to the given simulation context instance."""
Base.length(ctx::AbstractSimContext) = error("length is not yet implemented for ", typeof(ctx))

"""
Returns a 2-tulple of RemoteChannels for queuing contraction jobs and amplitudes respectively.

Also spawns an asynchronous feeder task to populate the job queue.
"""
start_queues(ctx::AbstractSimContext) = error("start_queues is not yet implemented for ", typeof(ctx))

"""Returns the i-th bitstring a simulation context should schedule contraction jobs for."""
get_bitstring!(ctx::AbstractSimContext, i::Integer) = error("get_bitstring! is not yet implemented for ", typeof(ctx))

"""Returns the i-th slice of an amplitude a simulation context should schedule a contraction job for."""
get_slice(ctx::AbstractSimContext, i::Integer) = error("get_slice is not yet implemented for ", typeof(ctx))

"""Returns the i-th contraction job, ie a (bitstring, slice) tuple, to be scheduled."""
get_contraction_job(ctx::AbstractSimContext, i::Integer) = error("get_contraction_job is not yet implemented for ", typeof(ctx))

"""Collect the given results on the root MPI rank."""
collect_results(ctx::AbstractSimContext, results, root, comm) = error("collect_results is not yet implemented for ", typeof(ctx))

"""Write the given results to a file."""
save_results(ctx::AbstractSimContext, results, output_file="") = error("save_results is not yet implemented for ", typeof(ctx))

"""Begin collecting and processing amplitudes from the given amplitude queue."""
(ctx::AbstractSimContext)(amps_queue) = error(typeof(ctx), " is not yet callable")


#===================================================#
# Concrete Implementations of AbstractSimContext
#===================================================#
include("list_simulation.jl")
include("uniform_simulation.jl")
include("rejection_simulation.jl")


#===================================================#
# Convenience Functions
#===================================================#
"""
    schedule_contraction_jobs(ctx::AbstractSimContext, jobs_queue::RemoteChannel)

Queue the contraction jobs assigned to the given simulation context in the given jobs queue.
"""
function schedule_contraction_jobs(ctx::AbstractSimContext, jobs_queue::RemoteChannel)
    for (bitstring, slice) in ctx
        put!(jobs_queue, (bitstring, slice))
    end
end

# Iterating over a simulation context should produce the contraction jobs assinged to it.
Base.iterate(ctx::AbstractSimContext) = iterate(ctx, 1)

function Base.iterate(ctx::AbstractSimContext, state::Integer)
    state > length(ctx) && return nothing
    slice_i, bitstring_j = get_contraction_job(ctx, state)
    (get_bitstring!(ctx, bitstring_j), get_slice(ctx, slice_i)), state + 1
end

"""
    SimulationContext(param_file::Sting, cg::ComputeGraph, rank::Integer=0, comm_size::Integer=1)

Returns an instance of the simulation context specified in the given parameter file.

Slice parameters are extracted from the given ComputeGraph and contraction jobs are assinged to the
return simulation context based on the given MPI rank and comm size.
"""
function SimulationContext(param_file::String, cg::ComputeGraph, rank::Integer=0, comm_size::Integer=1)
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

"""Return a batch of contraction jobs based on MPI rank and comm size."""
function get_jobs(all_jobs, rank, comm_size)
    num_jobs = length(all_jobs)
    all_jobs[start_stop(num_jobs, rank, comm_size)]
end

"""Returns a range indexing contraction jobs based on the given MPI rank and comm size."""
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