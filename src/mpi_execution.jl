using MPI
using DataStructures

"""
    partition(params, comm::MPI.Comm)

Identifies and returns the parameter partitions to be computed by this process and
the sizes of all partitions on the communicator.

The parameter space is divided linearly and any unbalanced work is assigned to 
the last process `rank == world_size-1`.
This will result in `length(params) % world_size` additional work items so could
result in inbalance at large scale.
Due to this imbalance, it is necessary to return the partition sizes to the caller
so it can decided whether is can call `MPI.Gather` (if all partitions are the same)
or MPI.Gatherv (if partition sizes differ).
"""
function partition(params, comm::MPI.Comm)
    my_rank = MPI.Comm_rank(comm)
    world_size = MPI.Comm_size(comm)

    partition_size = div(length(params), world_size)
    
    #TODO: Just populate as many nodes as possible?
    @assert partition_size != 0 "Not enough work for the allocated nodes"

    lower_bounds = [1 + rank * partition_size for rank in 0:world_size-1]
    upper_bounds = [lower_bound + partition_size - 1 for lower_bound in lower_bounds]

    if last(upper_bounds) != length(params)
        upper_bounds[end] = length(params)
    end

    my_lower_bound = lower_bounds[my_rank + 1]
    my_upper_bound = upper_bounds[my_rank + 1]

    partition_sizes = length.([lb:ub for (lb,ub) in zip(lower_bounds, upper_bounds)])

    params[my_lower_bound:my_upper_bound], partition_sizes
end

"""
    gather(local_results::Dict{String, T}, partition_sizes::Vector{Int}, root_rank::Int, comm::MPI.Comm;
           num_qubits = Sys.WORD_SIZE) where {T}

Gathers the results from all workers to produce a single Dict containing the probabilities
of all sampled amplitudes.
Probabilities of the same amplitudes computed on different ranks are summed.

This is required as `Dict`s with `String` keys may not be passed to MPI routines.

Returns the required result for the root_rank and an empty Dict for all others.
"""
function gather(local_results::Dict{String, T}, partition_sizes::Vector{Int}, root_rank::Int, comm::MPI.Comm;
                num_qubits = Sys.WORD_SIZE) where {T}
    # Convert the Dict of results into an Array of Tuples with the amplitude bitstring is parsed to a decimal number
    bitstype_local_results = [parse(Int, p.first; base=2) => p.second for p in collect(local_results)]

    # Check if all the partition_sizes are the same and call the correct gather function as required
    #
    # The current implementation offloads additional work to the last rank so check that first for a
    # quick result. This approach maintains generality if the definition of partition_sizes changes.
    if (all(x -> x==last(partition_sizes), partition_sizes))
        gathered_results = MPI.Gather(bitstype_local_results, root_rank, comm)
    else
        if MPI.Comm_rank(comm) == root_rank
            gathered_results = similar(bitstype_local_results, sum(partition_sizes))
            MPI.Gatherv!(bitstype_local_results, VBuffer(gathered_results, partition_sizes), root_rank, comm)
        else
            MPI.Gatherv!(bitstype_local_results, nothing, root_rank, comm)
        end
    end
    
    results = Dict{String, ComplexF32}()
    if MPI.Comm_rank(comm) == root_rank
        accumulator = DefaultDict{String, T}(T(0))

        for (amplitude, probability) in gathered_results
            amplitude_str = last(bitstring(amplitude), num_qubits)
            accumulator[amplitude_str] += probability
        end

        merge!(results, accumulator)
    end

    return results
end


"""
    execute(dsl_file::String, param_file::String, input_file::String, output_file::String, comm::MPI.Comm)

    Distributed version of `execute`.
"""
function execute(dsl_file::String, param_file::String, input_file::String, output_file::String, comm::MPI.Comm)
    root_rank = 0
    my_rank = MPI.Comm_rank(comm)
    world_size = MPI.Comm_size(comm)

    if output_file == ""
        output_file = input_file
    end

    if my_rank == root_rank
        commands = parse_dsl(dsl_file)
        params = Parameters(param_file)
    else
        commands = nothing
        params = nothing
    end

    commands = MPI.bcast(commands, root_rank, comm)
    params = MPI.bcast(params, root_rank, comm)

    local_params, partition_sizes = partition(params, comm)

    ctx = QXContext(commands, local_params, input_file, output_file)
    local_results = execute!(ctx)

    results = gather(local_results, partition_sizes, root_rank, comm; num_qubits=num_qubits(params))

    if my_rank == root_rank
        println(results)
        JLD.save(output_file, "results", results)
    end

    return results
end