module Execution

export QXContext, execute!, timer_output, reduce_nodes
export execute, partition, gather
export set_output_bitstring, set_partition_parameters

using DataStructures
import MPI
import JLD2
import FileIO
import LinearAlgebra
import TensorOperations
import QXContexts.Logger: @debug
using TimerOutputs
using OMEinsum
using QXContexts.DSL
using QXContexts.Param

# Import MPI-specific functions
include("mpi_execution.jl")
import .MPIExecution: gather, partition

const timer_output = TimerOutput()
if haskey(ENV, "QXRUN_TIMER")
    timeit_debug_enabled() = return true # Function fails to be defined by enable_debug_timings
    TimerOutputs.enable_debug_timings(Execution)
end

"""
    QXContext(cmds::CommandList, input_file::String, output_file::String)

A structure to represent and maintain the current state of a QXContexts execution.
"""
struct QXContext{T}
    open_bonds::Vector{Symbol}
    partition_params::Dict{Symbol, Int}
    cmds::CommandList
    data::Dict{Symbol, T}
end

function QXContext(::Type{T}, cmds::CommandList, partition_params::Vector{Symbol}, input_file::String, output_file::String) where {T <: AbstractArray}
    # find the outputs command to get number of outputs
    num_open_bonds = cmds[findfirst(x -> x isa OutputsCommand, cmds)].num_outputs
    open_bonds = [Symbol("o$i") for i = 1:num_open_bonds]

    # load input data and match with symbols from load commands
    input_data = Dict(Symbol(x) => convert(T, y) for (x, y) in pairs(FileIO.load(input_file)))
    data = Dict{Symbol, T}()
    for load_cmd in filter(x -> x isa LoadCommand, cmds)
        data[load_cmd.name] = input_data[load_cmd.label]
    end

    partition_params = Dict{Symbol, Int}(x => 1 for x in partition_params)
    # for view_cmd in filter(x -> x isa ViewCommand, cmds)
    #     partition_params[view_cmd.bond_range] = -1
    # end

    cmds = filter(x -> typeof(x) in [NconCommand, ViewCommand, SaveCommand], cmds)

    QXContext{T}(open_bonds, partition_params, cmds, data)
end

function QXContext(cmds::CommandList, partition_params::Vector{Symbol}, input_file::String, output_file::String)
    QXContext(Array{ComplexF32}, cmds, partition_params, input_file, output_file)
end

function set_output_bitstring(ctx::QXContext{T}, bitstring::String) where {T <: AbstractArray}
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

function set_partition_parameters(ctx::QXContext, partition_params::Dict{Symbol, Int})
    for k in keys(partition_params)
        ctx.partition_params[k] = partition_params[k]
    end
end


###############################################################################
# Individual command execution functions
###############################################################################

# """
#     execute!(cmd::LoadCommand, ctx::ExecutionCtx{T}) where {T}

# Execute a load DSL command
# """
# function execute!(cmd::LoadCommand, ctx::QXContext{T}) where {T}
#     @timeit_debug timer_output "DSL_load" begin
#         ctx.data[cmd.name] = FileIO.load(ctx.input_file, String(cmd.label))
#     @debug "Load DSL command: name=$(cmd.name), input_file=$(ctx.input_file), label=$(String(cmd.label))"
#     end
#     nothing
# end

"""
    execute!(cmd::SaveCommand, ctx::ExecutionCtx{T}) where {T}

Execute a save DSL command
"""
function execute!(cmd::SaveCommand, ctx::QXContext{T}) where {T}
    @timeit_debug timer_output "DSL_save" begin
        # JLD2.jldopen(ctx.output_file, "a+") do file
            # write(file, String(cmd.label), ctx.data[cmd.name])
        # end
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
        if haskey(ctx.partition_params, cmd.bond_range)
            dims = size(ctx.data[cmd.target])
            bond_val = ctx.partition_params[cmd.bond_range]
            view_index_list = [i == cmd.bond_index ? UnitRange(bond_val, bond_val) : UnitRange(1, dims[i]) for i in 1:length(dims)]
            ctx.data[cmd.name] = @view ctx.data[cmd.target][view_index_list...]
        else
            ctx.data[cmd.name] = ctx.data[cmd.target]
        end
    @debug "view DSL command: $(cmd.name) = $(cmd.target)[$(view_index_list)]"
    end
    nothing
end


###############################################################################
# Execution functions
###############################################################################

# """
#     reduce_nodes(nodes::Dict{Symbol, Vector{T}})

# Recombine slices results
# """
# function reduce_nodes(nodes::AbstractDict{Symbol, Vector{T}}) where {T}
#     sum(reduce((x,y) -> x .* y, values(nodes)))
# end

# """
#     execute!(ctx::QXContext{T}) where T

# Run a given context.
# """
# function execute!(ctx::QXContext{T}) where T
#     results = Dict{String, eltype(T)}([k => 0 for k in ctx.params.amplitudes])

#     input_file = JLD2.jldopen(ctx.input_file, "r")

#     split_idx = findfirst(x -> !(x isa LoadCommand) && !(x isa ParametricCommand{LoadCommand}), ctx.cmds)
#     # static I/O commands do not depends on any substitutions and can be run
#     # once for all combinations of output qubits and slices
#     static_iocmds, parametric_iocmds = begin
#         iocmds = ctx.cmds[1:split_idx-1]
#         pred = x -> x isa LoadCommand
#         filter(pred, iocmds), filter(!pred, iocmds)
#     end
#     cmds = ctx.cmds[split_idx:end]

#     length(parametric_iocmds) != 0 && error("parametric io commands currently unsupported")

#     # Figure out the names of the tensors being loaded by iocmds
#     statically_loaded_tensors = [x.name for x in static_iocmds]
#     # Remove any delete commands that delete tensors just loaded
#     filter!(x -> !(x isa DeleteCommand && x.label in statically_loaded_tensors), cmds)

#     # Remove parametric delete commmands that will delete output tensors
#     filter!(x -> !(x isa ParametricCommand{DeleteCommand} && startswith(x.args, "\$o")), cmds)

#     #FIXME: I also don't think this is necessary anymore
#     #FIXME: This is not nice - shouldn't be exposing the ParametricCommand implementation
#     parametrically_loaded_tensors = [split(x.args, " ")[1] for x in parametric_iocmds]
#     # Remove any delete commands that delete tensors just loaded
#     filter!(x -> !(x isa ParametricCommand{DeleteCommand} && x.args in parametrically_loaded_tensors), cmds)

#     for iocmd in static_iocmds
#         ctx.data[iocmd.name] = read(input_file, String(iocmd.label))
#     end

#     # run command substitution
#     for substitution_set in ctx.params
#         for substitution in substitution_set
#             @timeit_debug timer_output "Perform substitution" subbed_cmds = apply_substitution(cmds, substitution)
#             # Run each of the DSL commands in order
#             for cmd in subbed_cmds
#                 #TODO: Without checkpointing, etc. the SaveCommand *should* be the last command
#                 #      so its execution can probably be pulled out of this loop
#                 if cmd isa SaveCommand
#                     # The data, `ctx.data[cmd.name]`, needs to be dereferenced with `[]`
#                     # Although it's a scalar, it will be within an N-d array
#                     results[substitution_set.amplitude] += ctx.data[cmd.name][]
#                 else
#                     #TODO: This could be moved out of the conditional entirely
#                     #      but the symbol we're saving as would need to be updated to prevent overwrites
#                     execute!(cmd, ctx)
#                 end
#             end
#         end
#     end

#     close(input_file)

#     if haskey(ENV, "QXRUN_TIMER")
#         io = IOBuffer();
#         print_timer(io, timer_output)
#         op = String(take!(io))
#         @info "Timed calls:\n$(op)\n"
#     end

#     #TODO: These results could also be written to `ctx.output_file`
#     return results
# end

function execute!(ctx::QXContext)
    for cmd in ctx.cmds
        execute!(cmd, ctx)
    end
    ctx.data[:output][]
end


"""
    execute(dsl_file::String,
            param_file::String,
            input_file::String,
            output_file::String,
            comm::Union{MPI.Comm, Nothing}=nothing)
"""
function execute(dsl_file::String,
                 param_file::String,
                 input_file::String,
                 output_file::String,
                 comm::Union{MPI.Comm, Nothing}=nothing;
                 max_amplitudes::Union{Int, Nothing}=nothing,
                 max_parameters::Union{Int, Nothing}=nothing)

    if comm !== nothing
        root_rank = 0
        my_rank = MPI.Comm_rank(comm)
        world_size = MPI.Comm_size(comm)
    end

    commands = parse_dsl(dsl_file)
    bitstrings, partition_params = parse_parameters(param_file,
                                                    max_amplitudes=max_amplitudes, max_parameters=max_parameters)

    ctx = QXContext(commands, collect(keys(partition_params)), input_file, output_file)

    results = Dict{String, ComplexF32}()
    amplitude = ComplexF32(0)
    for bitstring in bitstrings
        set_output_bitstring(ctx, bitstring)
        amplitude = ComplexF32(0)
        for p in CartesianIndices(Tuple(values(partition_params)))
            set_partition_parameters(ctx, Dict{Symbol, Int}(k => v for (k, v) in zip(keys(partition_params), Tuple(p))))
            amplitude += execute!(ctx)
        end
        results[bitstring] = amplitude
    end
    # if comm !== nothing
    #     results = gather(results, partition_sizes, root_rank, comm; num_qubits=num_qubits(params))
    # end

    # if comm === nothing || my_rank == root_rank
    JLD2.@save output_file results
    # end

    return results
end


end