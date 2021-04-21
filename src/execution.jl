module Execution

export QXContext, execute!, timer_output, reduce_nodes
export execute
export set_open_bonds!, set_slice_vals!
export compute_amplitude!

using DataStructures
import MPI
import JLD2
import FileIO
import LinearAlgebra
import TensorOperations
import QXContexts.Logger: @debug
using TimerOutputs
using Random
using OMEinsum
using QXContexts.DSL
using QXContexts.Param
using QXContexts.Sampling
import QXContexts

const timer_output = TimerOutput()
if haskey(ENV, "QXRUN_TIMER")
    timeit_debug_enabled() = return true # Function fails to be defined by enable_debug_timings
    TimerOutputs.enable_debug_timings(Execution)
end

"""
Context in which to perform contractions and other tesnor manipulation operations. Also
manages storage for tensor operations.
"""
struct QXContext{T}
    open_bonds::Vector{Symbol}
    slice_syms::Vector{Symbol}
    slice_dims::Vector{Int}
    slice_vals::Vector{Int}
    cmds::CommandList
    data::Dict{Symbol, T}
end

"""
    QXContext(::Type{T},
              cmds::CommandList,
              partition_dims::OrderedDict{Symbol, Int},
              input_file::String) where {T <: AbstractArray})

Constructor for QXContext which loads data and prepares context for processing
"""
function QXContext(::Type{T},
                   cmds::CommandList,
                   partition_dims::OrderedDict{Symbol, Int},
                   input_file::String) where {T <: AbstractArray}
    # find the outputs command to get number of outputs
    num_open_bonds = cmds[findfirst(x -> x isa OutputsCommand, cmds)].num_outputs
    open_bonds = [Symbol("o$i") for i = 1:num_open_bonds]

    # load input data and match with symbols from load commands
    input_data = Dict(Symbol(x) => convert(T, y) for (x, y) in pairs(FileIO.load(input_file)))
    data = Dict{Symbol, T}()
    for load_cmd in filter(x -> x isa LoadCommand, cmds)
        data[load_cmd.name] = input_data[load_cmd.label]
    end

    slice_syms, slice_dims, slice_vals = Symbol[], Int[], Int[]
    for k in keys(partition_dims)
        push!(slice_syms, k)
        push!(slice_dims, partition_dims[k])
        push!(slice_vals, -1)
    end

    cmds = filter(x -> typeof(x) in [NconCommand, ViewCommand, SaveCommand], cmds)

    QXContext{T}(open_bonds, slice_syms, slice_dims, slice_vals, cmds, data)
end

"""Sets default datatype to ComplexF32"""
function QXContext(cmds::CommandList,
                   partition_dims::OrderedDict{Symbol, Int},
                   input_file::String)
    QXContext(Array{ComplexF32}, cmds, partition_dims, input_file)
end

"""
    set_open_bonds!(ctx::QXContext{T}, bitstring::String) where {T <: AbstractArray}

Given a bitstring, set the open bonds to values so contracting the network will
calculate the amplitude of this bitstring
"""
function set_open_bonds!(ctx::QXContext{T}, bitstring::String) where {T <: AbstractArray}
    for (i, bond) in enumerate(ctx.open_bonds)
        if bitstring[i] == '0'
            ctx.data[bond] = convert(T, [1,0])
        elseif bitstring[i] == '1'
            ctx.data[bond] = convert(T, [0,1])
        else
            error("$(bitstring[i]) not supported in bitstring")
        end
    end
end

"""
    set_slice_vals!(ctx::QXContext, slice_values::Vector{Int})

For each bond that is being sliced set the dimension to slice on.
"""
function set_slice_vals!(ctx::QXContext, slice_values::Vector{Int})
    ctx.slice_vals[:] = slice_values
end

"""
Data structure that implements iterator interface for iterating over multi-dimensional
objects with configurable start and end points.
"""
struct SliceIterator
    iter::CartesianIndices
    start::Int
    stop::Int
end

"""
    SliceIterator(dims::Vector{Int}, start::Int=1, stop::Int=-1)

Constructor for slice iterator which takes dimensions as argument
"""
function SliceIterator(dims::Vector{Int}, start::Int=1, stop::Int=-1)
    iter = CartesianIndices(Tuple(dims))
    if stop == -1 stop = length(iter) end
    SliceIterator(iter, start, stop)
end

"""
    SliceIterator(dims::Vector{Int}, start::Int=1, stop::Int=-1)

Data structure that implements iterator interface for iterating over multi-dimensional
objects with configurable start and end points.
"""
SliceIterator(ctx::QXContext, args...) = SliceIterator(ctx.slice_dims, args...)

"""Implement require iterator interface functions"""
Base.iterate(a::SliceIterator) = length(a) == 0 ? nothing : (Int[Tuple(a.iter[a.start])...], a.start)
Base.iterate(a::SliceIterator, state) = length(a) <= (state + 1 - a.start) ? nothing : (Int[Tuple(a.iter[state + 1])...], state + 1)
Base.length(a::SliceIterator) = a.stop - a.start + 1
Base.eltype(::SliceIterator) = Vector{Int}

"""Function for reducing over amplitude contributions from each slice. For non-serial
contexts, contributions are summed over"""
reduce_slices(::QXContext, a) = a

"""Function for reducing over calculated amplitudes. For non-serial contexts, contributions
are gathered"""
reduce_amplitudes(::QXContext, a) = a

"""Function for reducing over calculated amplitudes. For non-serial contexts, contributions
are gathered"""
BitstringIterator(::QXContext, bitstrings) = bitstrings

"""
    write_results(::QXContext, results, output_file)

Save results from calculations for the given
"""
function write_results(::QXContext, results, output_file)
    JLD2.@save output_file results
end

"""Function to create a scalar with zero value of appropriate data-type for given contexct"""
Base.zero(::QXContext{T}) where T = zero(eltype(T))

###############################################################################
# Individual command execution functions
###############################################################################

"""
    execute!(cmd::SaveCommand, ctx::ExecutionCtx{T}) where {T}

Execute a save DSL command
"""
function execute!(cmd::SaveCommand, ctx::QXContext{T}) where {T}
    @timeit_debug timer_output "DSL_save" begin
        ctx.data[cmd.label] = ctx.data[cmd.name]
    @debug "Save DSL command: name=$(cmd.name), label=$(String(cmd.label))"
    end
    nothing
end

"""
    execute!(cmd::ReshapeCommand, ctx::ExecutionCtx{T}) where {T}

Execute a reshape DSL command
"""
function execute!(cmd::ReshapeCommand, ctx::QXContext{T}) where {T}
    @timeit_debug timer_output "DSL_reshape" begin
        tensor_dims = size(ctx.data[cmd.name])
        new_dims = [prod([tensor_dims[y] for y in x]) for x in cmd.dims]
        ctx.data[cmd.name] = reshape(ctx.data[cmd.name], new_dims...)
    @debug "Reshape DSL command: name=$(cmd.name), dims=$(tensor_dims), new_dims=$(new_dims)"
    end
    nothing
end

"""
    execute!(cmd::PermuteCommand, ctx::ExecutionCtx{T}) where {T}

Execute a permute DSL command
"""
function execute!(cmd::PermuteCommand, ctx::QXContext{T}) where {T}
    @timeit_debug timer_output "DSL_permute" begin
        ctx.data[cmd.name] = permutedims(ctx.data[cmd.name], cmd.dims)
    @debug "Permute DSL command: name=$(cmd.name), dims=$(cmd.dims)"
    end
    nothing
end

"""
    execute!(cmd::NconCommand, ctx::ExecutionCtx{T}) where {T}

Execute an ncon DSL command
"""
function execute!(cmd::NconCommand, ctx::QXContext{T}) where {T}
    output_idxs = Tuple(cmd.output_idxs)
    left_idxs = Tuple(cmd.left_idxs)
    right_idxs = Tuple(cmd.right_idxs)

    @timeit_debug timer_output "DSL_ncon" begin
        @debug "ncon DSL command: $(cmd.output_name)[$(output_idxs)] = $(cmd.left_name)[$(cmd.left_idxs)] * $(cmd.right_name)[$(cmd.right_idxs)]"
        @debug "ncon shapes: left_size=$(size(ctx.data[cmd.left_name])), right_size=$(size(ctx.data[cmd.right_name]))"
        ctx.data[cmd.output_name] = EinCode((left_idxs, right_idxs), output_idxs)(ctx.data[cmd.left_name], ctx.data[cmd.right_name])
    end
    nothing
end

"""
    execute!(cmd::ViewCommand, ctx::ExecutionCtx{T}) where {T}

Execute a view DSL command
"""
function execute!(cmd::ViewCommand, ctx::QXContext{T}) where {T}
    @timeit_debug timer_output "DSL_view" begin
        slice_idx = findfirst(x -> x == cmd.slice_sym, ctx.slice_syms)
        if slice_idx !== nothing
            dims = size(ctx.data[cmd.target])
            bond_val = ctx.slice_vals[slice_idx]
            view_index_list = [i == cmd.bond_index ? UnitRange(bond_val, bond_val) : UnitRange(1, dims[i]) for i in 1:length(dims)]
            ctx.data[cmd.name] = @view ctx.data[cmd.target][view_index_list...]
        else
            ctx.data[cmd.name] = ctx.data[cmd.target]
        end
    @debug "view DSL command: $(cmd.name) = $(cmd.target)[$(view_index_list)]"
    end
    nothing
end

"""
    execute!(ctx::QXContext)

Execute all commands for given context
"""
function execute!(ctx::QXContext)
    for cmd in ctx.cmds
        execute!(cmd, ctx)
    end
    ctx.data[:output][]
end

"""
    compute_amplitude!(ctx, bitstring::String)

Calculate a single amplitude with the given context and bitstring. Involves a sum over
contributions from each slice.
"""
function compute_amplitude!(ctx, bitstring::String)
    set_open_bonds!(ctx, bitstring)
    amplitude = zero(ctx)
    for p in SliceIterator(ctx)
        set_slice_vals!(ctx, p)
        amplitude += execute!(ctx)
    end
    reduce_slices(ctx, amplitude)
end

include("mpi_execution.jl")

"""
    execute(dsl_file::String,
            param_file::String,
            input_file::String,
            output_file::String,
            comm::Union{MPI.Comm, Nothing}=nothing;
            sub_comm_size::Int=1,
            max_amplitudes::Union{Int, Nothing}=nothing,
            max_parameters::Union{Int, Nothing}=nothing)

Main entry point for running calculations. Loads input data, runs computations and
writes results to output files.
"""
function execute(dsl_file::String,
                 param_file::String,
                 input_file::String,
                 output_file::String,
                 comm::Union{MPI.Comm, Nothing}=nothing;
                 sub_comm_size::Int=1,
                 max_amplitudes::Union{Int, Nothing}=nothing,
                 max_parameters::Union{Int, Nothing}=nothing)

    commands = parse_dsl(dsl_file)

    bitstrings, partition_params = parse_parameters(param_file,
                                                    max_amplitudes=max_amplitudes, max_parameters=max_parameters)

    ctx = QXContext(commands, partition_params, input_file)
    if comm !== nothing
        ctx = QXMPIContext(ctx, comm, sub_comm_size)
    end

    bitstring_iter = BitstringIterator(ctx, bitstrings)
    results = Array{ComplexF32, 1}(undef, length(bitstring_iter))
    for (i, bitstring) in enumerate(bitstring_iter)
        results[i] = compute_amplitude!(ctx, bitstring)
    end
    results = reduce_amplitudes(ctx, results)

    write_results(ctx, results, output_file)

    return results
end

end