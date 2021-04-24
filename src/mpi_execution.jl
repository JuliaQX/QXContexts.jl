"""
General utility functions for working with MPI and partitions
"""

export get_rank_size
export get_rank_start

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

function get_rank_range(n::Integer, size::Integer, rank::Integer)
    start = get_rank_start(n, size, rank)
    UnitRange(start, start + get_rank_size(n, size, rank) - 1)
end

"""
    QXMPIContext(cmds::CommandList, input_file::String, output_file::String)

A structure to represent and maintain the current state of a QXContexts execution.
"""
struct QXMPIContext{T}
    serial_ctx::QXContext{T}
    comm::MPI.Comm # communicator containing all ranks
    sub_comm::MPI.Comm # communicator containing ranks in subgroup used for partitions
    root_comm::MPI.Comm # communicator containing root rank from each subgroup
end

function QXMPIContext(ctx::QXContext{T}, comm::MPI.Comm, sub_comm_size::Int=1) where T
    @assert MPI.Comm_size(comm) % sub_comm_size == 0 "sub_comm_size must divide comm size evenly"
    sub_comm = MPI.Comm_split(comm, MPI.Comm_rank(comm) ÷ sub_comm_size, MPI.Comm_rank(comm) % sub_comm_size)
    root_comm = MPI.Comm_split(comm, MPI.Comm_rank(comm) % sub_comm_size, MPI.Comm_rank(comm) ÷ sub_comm_size)
    QXMPIContext{T}(ctx, comm, sub_comm, root_comm)
end

set_open_bonds!(ctx::QXMPIContext, args...) = set_open_bonds!(ctx.serial_ctx, args...)
set_slice_vals!(ctx::QXMPIContext, args...) = set_slice_vals!(ctx.serial_ctx, args...)

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

function reduce_slices(ctx::QXMPIContext, a)
    total = MPI.Reduce(a, MPI.SUM, 0, ctx.sub_comm)
    if MPI.Comm_rank(ctx.sub_comm) == 0
        return total
    else
        return a
    end
end

function reduce_amplitudes(ctx::QXMPIContext, a)
    if MPI.Comm_rank(ctx.sub_comm) == 0
        return MPI.Gather(a, 0, ctx.root_comm)
    end
end

function BitstringIterator(ctx::QXMPIContext, bitstrings)
    total_length = length(bitstrings)
    args = (total_length, MPI.Comm_size(ctx.root_comm), MPI.Comm_rank(ctx.root_comm))
    bitstrings[get_rank_range(args...)]
end

function execute!(ctx::QXMPIContext)
    execute!(ctx.serial_ctx)
end

function write_results(ctx::QXMPIContext, results, output_file)
    if MPI.Comm_rank(ctx.comm) == 0 JLD2.@save output_file results end
end

Base.zero(::QXMPIContext{T}) where T = zero(eltype(T))