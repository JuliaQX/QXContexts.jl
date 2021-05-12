"""
General utility functions for working with MPI and partitions
"""

export get_rank_size
export get_rank_start
export get_rank_range

"""
    get_rank_size(n::Integer, size::Integer, rank::Integer)

Partition n items among processes of communicator of size size and return the size of the
given rank. Algorithm used is to:
1. Divide items equally among processes
2. Spread remainder over ranks in ascending order of rank number
"""
function get_rank_size(n::Integer, size::Integer, rank::Integer)
    (n ÷ size) + ((n % size) >= (rank + 1))
end

"""
    get_rank_start(n::Integer, size::Integer, rank::Integer)

Partition n items among processes of communicator of size size and return the starting of the
given rank. Algorithm used is to:
1. Divide items equally among processes
2. Spread remainder over ranks in ascending order of rank number
"""
function get_rank_start(n::Integer, size::Integer, rank::Integer)
    start = rank * (n ÷ size) + 1
    start + min(rank, n % size)
end

"""
    get_rank_range(n::Integer, size::Integer, rank::Integer)

Partition n items among processes of communicator of size size and return a range over these
indices.
"""
function get_rank_range(n::Integer, size::Integer, rank::Integer)
    start = get_rank_start(n, size, rank)
    UnitRange(start, start + get_rank_size(n, size, rank) - 1)
end

"""
MPI context which can be used to perform distribted computations
"""
struct QXMPIContext
    serial_ctx::QXContext
    comm::MPI.Comm # communicator containing all ranks
    sub_comm::MPI.Comm # communicator containing ranks in subgroup used for partitions
    root_comm::MPI.Comm # communicator containing root rank from each subgroup
end

"""
    QXMPIContext(ctx::QXContext, comm::MPI.Comm, sub_comm_size::Int=1)

Constructor for QXMPIContext that initialises new sub-communicators for managing groups
of nodes.
"""
function QXMPIContext(ctx::QXContext, comm::MPI.Comm, sub_comm_size::Int=1)
    @assert MPI.Comm_size(comm) % sub_comm_size == 0 "sub_comm_size must divide comm size evenly"
    sub_comm = MPI.Comm_split(comm, MPI.Comm_rank(comm) ÷ sub_comm_size, MPI.Comm_rank(comm) % sub_comm_size)
    root_comm = MPI.Comm_split(comm, MPI.Comm_rank(comm) % sub_comm_size, MPI.Comm_rank(comm) ÷ sub_comm_size)
    QXMPIContext(ctx, comm, sub_comm, root_comm)
end

"""Implementes set_open_bonds! for QXMPIContexts"""
set_open_bonds!(ctx::QXMPIContext, args...) = set_open_bonds!(ctx.serial_ctx, args...)
"""Implementes set_slice_vals! for QXMPIContexts"""
set_slice_vals!(ctx::QXMPIContext, args...) = set_slice_vals!(ctx.serial_ctx, args...)

"""
    SliceIterator(ctx::QXMPIContext)

Function which creates a SliceIterator given a QXMPIContext structure
"""
function SliceIterator(ctx::QXMPIContext)
    serial_iter = SliceIterator(ctx.serial_ctx)
    total_length = length(serial_iter)
    args = (total_length,
            MPI.Comm_size(ctx.sub_comm),
            MPI.Comm_rank(ctx.sub_comm))
    SliceIterator(ctx.serial_ctx.slice_dims,
                  get_rank_start(args...),
                  get_rank_start(args...) + get_rank_size(args...) - 1
    )
end

"""
    reduce_slices(ctx::QXMPIContext, a)

Function to sum amplitude contributions
"""
function reduce_slices(ctx::QXMPIContext, a)
    total = MPI.Reduce(a, MPI.SUM, 0, ctx.sub_comm)
    if MPI.Comm_rank(ctx.sub_comm) == 0
        return total
    else
        return a
    end
end

"""
    reduce_results(ctx::QXMPIContext, results::Samples)

Function to gather amplitudes and samples from sub-communicators.
"""
function reduce_results(ctx::QXMPIContext, results::Samples)
    if MPI.Comm_rank(ctx.sub_comm) == 0
        bitstrings = keys(results.amplitudes)
        num_qubits = length(first(bitstrings))

        bitstrings_as_ints = parse.(UInt64, bitstrings, base=2)
        amplitudes = [results.amplitudes[bitstring] for bitstring in bitstrings]
        samples = [results.bitstrings_counts[bitstring] for bitstring in bitstrings]

        bitstrings_as_ints = MPI.Gather(bitstrings_as_ints, 0, ctx.root_comm)
        amplitudes = MPI.Gather(amplitudes, 0, ctx.root_comm)
        samples = MPI.Gather(samples, 0, ctx.root_comm)

        bitstrings = reverse.(digits.(bitstrings_as_ints, base=2, pad=num_qubits))
        bitstrings = [prod(string.(bits)) for bits in bitstrings]
        amplitudes = Dict{String, eltype(amplitudes)}(bitstrings .=> amplitudes)
        bitstrings = DefaultDict(0, Dict{String, Int}(bitstrings .=> samples))
    end
    Samples(bitstrings, amplitudes)
end

"""
    BitstringIterator(ctx::QXMPIContext, bitstrings)

Create a bitstring iterator for a QXMPIContext from a global bitstring iterator
"""
function BitstringIterator(ctx::QXMPIContext, bitstrings)
    total_length = length(bitstrings)
    args = (total_length, MPI.Comm_size(ctx.root_comm), MPI.Comm_rank(ctx.root_comm))
    bitstrings[get_rank_range(args...)]
end

"""Implement execute! for QXMPIContext"""
function execute!(ctx::QXMPIContext)
    execute!(ctx.serial_ctx)
end

"""
    write_results(ctx::QXMPIContext, results, output_file)

Function write results for QXMPIContext. Only writes from root process
"""
function write_results(ctx::QXMPIContext, results, output_file)
    if MPI.Comm_rank(ctx.comm) == 0
        amplitudes = results.amplitudes
        bitstrings_counts = results.bitstrings_counts
        JLD2.@save output_file amplitudes bitstrings_counts
    end
end

Base.zero(ctx::QXMPIContext) = zero(ctx.serial_ctx)