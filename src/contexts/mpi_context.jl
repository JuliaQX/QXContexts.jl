using MPI
using Lazy
using Logging

export QXMPIContext
export get_rank_size, get_rank_start, get_rank_range

# Implementation of QXMPIContext which provides a Context that can be used with MPI
#
# The QXMPIContext struct contains a reference to another context struct which is used
# to perform contractions for individual sets of slice values
#
# Utility functions get_rank_size, get_rank_start and get_rank_range are provided as
# generic utility functions for working with multiple processing ranks

"""MPI context which can be used to perform distribted computations"""
struct QXMPIContext <: AbstractContext
    serial_ctx::AbstractContext
    comm::MPI.Comm # communicator containing all ranks
    sub_comm::MPI.Comm # communicator containing ranks in subgroup, used for partitions
    root_comm::MPI.Comm # communicator containing ranks of matching rank from other sub_comms
end

"""
    QXMPIContext(ctx::QXContext, comm::MPI.Comm, sub_comm_size::Int=1)

Constructor for QXMPIContext that initialises new sub-communicators for managing groups
of nodes.
"""
function QXMPIContext(ctx::QXContext,
                      comm::Union{MPI.Comm, Nothing}=nothing;
                      sub_comm_size::Int=1)
    if comm === nothing
        if !MPI.Initialized()
            MPI.Init()
            @info "MPI Initialised"
        end
        comm = MPI.COMM_WORLD
    end
    @info "Number processes $(MPI.Comm_size(MPI.COMM_WORLD))"
    @assert MPI.Comm_size(comm) % sub_comm_size == 0 "sub_comm_size must divide comm size evenly"
    sub_comm = MPI.Comm_split(comm, MPI.Comm_rank(comm) ÷ sub_comm_size, MPI.Comm_rank(comm) % sub_comm_size)
    root_comm = MPI.Comm_split(comm, MPI.Comm_rank(comm) % sub_comm_size, MPI.Comm_rank(comm) ÷ sub_comm_size)
    QXMPIContext(ctx, comm, sub_comm, root_comm)
end

######################################################################################
#  Forward each of the methods to work with serial_ctx from the QXMPIContext
######################################################################################
@forward QXMPIContext.serial_ctx gettensor
@forward QXMPIContext.serial_ctx settensor!
@forward QXMPIContext.serial_ctx Base.getindex
@forward QXMPIContext.serial_ctx Base.setindex!
@forward QXMPIContext.serial_ctx Base.haskey
@forward QXMPIContext.serial_ctx Base.zeros
@forward QXMPIContext.serial_ctx Base.zero
@forward QXMPIContext.serial_ctx Base.eltype
@forward QXMPIContext.serial_ctx set_open_bonds!
@forward QXMPIContext.serial_ctx set_slice_vals!


"""Make struct callable"""
(ctx::QXMPIContext)(args...; kwargs...) = ctx.serial_ctx(args...; kwargs...)

"""
    compute_amplitude!(ctx, bitstring::String; num_slices=nothing)

Calculate a single amplitude with the given context and bitstring. Involves a sum over
contributions from each slice. Can optionally set the number of bonds. By default all slices
are used.
"""
function compute_amplitude!(ctx::QXMPIContext, bitstring::String; max_slices=nothing)
    set_open_bonds!(ctx, bitstring)
    amplitude = nothing
    si = SliceIterator(ctx.serial_ctx.cg, max_slices=max_slices)
    r = get_comm_range(ctx.sub_comm, length(si))
    for p in SliceIterator(si, r.start, r.stop)
        set_slice_vals!(ctx, p)
        if amplitude === nothing
            amplitude = ctx()
        else
            amplitude += ctx()
        end
    end
    # reduce across sub_communicator
    # TODO: replace reduce with batched reduce or use one-sided communication to accumulate
    # to root of sub_comm
    MPI.Reduce!(amplitude, +, 0, ctx.sub_comm)
    if MPI.Comm_rank(ctx.sub_comm) != 0
        return nothing
    end
    if ndims(amplitude) == 0 amplitude = amplitude[] end
    amplitude
end

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
    get_comm_range(comm::MPI.Comm, n::Integer)

Given a communicator and number of items, get the range for local rank
"""
function get_comm_range(comm::MPI.Comm, n::Integer)
    get_rank_range(n, MPI.Comm_size(comm), MPI.Comm_rank(comm))
end

"""
    ctxmap(f, ctx::QXMPIContext, items)

For each of the items in the local range apply the f function and return
the result.
"""
function ctxmap(f, ctx::QXMPIContext, items)
    map(f, items[get_comm_range(ctx.root_comm, length(items))])
end

"""
    ctxgather(ctx::QXMPIContext, items)

Gather local items to root rank
"""
function ctxgather(ctx::QXMPIContext, items)
    if MPI.Comm_rank(ctx.sub_comm) == 0
        return MPI.Gather(items, 0, ctx.root_comm)
    end
end

"""
    ctxreduce(f, ctx::QXMPIContext, items)

Reduce across items with funciton f
"""
function ctxreduce(f, ctx::QXMPIContext, items)
    if MPI.Comm_rank(ctx.sub_comm) == 0
        return MPI.Reduce(items, f, 0, MPI.root_comm)
    end
end