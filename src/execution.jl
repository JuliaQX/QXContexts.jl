module Execution

export QXContext, execute!, timer_output, reduce_nodes
export execute, partition, gather

using DataStructures

import JLD
import LinearAlgebra
import TensorOperations
import QXRun.Logger: @debug
using TimerOutputs
using QXRun.DSL
using QXRun.Param

# Import MPI-specific functions
include("mpi_execution.jl")
import .MPIExecution: execute, gather, partition

const timer_output = TimerOutput()
if haskey(ENV, "QXRUN_TIMER")
    timeit_debug_enabled() = return true # Function fails to be defined by enable_debug_timings
    TimerOutputs.enable_debug_timings(Execution)
end

"""
    QXContext(cmds::CommandList, params::Parameters, input_file::String, output_file::String)

A structure to represent and maintain the current state of a QXRun execution.
This structure will hold MPI rank information and is therefore responsible for
figuring out what segment of the work is its own.
"""
struct QXContext{T}
    cmds::CommandList
    params::Parameters
    input_file::String
    output_file::String
    data::Dict{Symbol, T}
end

function QXContext(::Type{T}, cmds::CommandList, params::Parameters, input_file::String, output_file::String) where {T <: AbstractArray}
    data = Dict{Symbol, T}()
    QXContext{T}(cmds, params, input_file, output_file, data)
end

function QXContext(cmds::CommandList, params::Parameters, input_file::String, output_file::String)
    QXContext(Array{ComplexF32}, cmds, params, input_file, output_file)
end

###############################################################################
# Individual command execution functions
###############################################################################

"""
    execute!(cmd::LoadCommand, ctx::ExecutionCtx{T}) where {T}

Execute a load DSL command
"""
function execute!(cmd::LoadCommand, ctx::QXContext{T}) where {T}
    @timeit_debug timer_output "DSL_load" begin
        ctx.data[cmd.name] = JLD.load(ctx.input_file, String(cmd.label))
    @debug "Load DSL command: name=$(cmd.name), input_file=$(ctx.input_file), label=$(String(cmd.label))"
    end
    nothing
end

"""
    execute!(cmd::SaveCommand, ctx::ExecutionCtx{T}) where {T}

Execute a save DSL command
"""
function execute!(cmd::SaveCommand, ctx::QXContext{T}) where {T}
    @timeit_debug timer_output "DSL_save" begin
        mode = isfile(ctx.output_file) ? "r+" : "w"
        JLD.jldopen(ctx.output_file, mode) do file
            file[String(cmd.label)] = ctx.data[cmd.name]
        end
    @debug "Save DSL command: name=$(cmd.name), output_file=$(ctx.output_file), label=$(String(cmd.label))"
    end
    nothing
end

"""
    execute!(cmd::DeleteCommand, ctx::ExecutionCtx{T}) where {T}

Execute a delete DSL command
"""
function execute!(cmd::DeleteCommand, ctx::QXContext{T}) where {T}
    @timeit_debug timer_output "DSL_delete" begin
        delete!(ctx.data, cmd.label)
    @debug "Delete DSL command: label=$(String(cmd.label))"
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
    left_idxs = Tuple(cmd.left_idxs)
    right_idxs = Tuple(cmd.right_idxs)

    t_symdiff = Tuple(TensorOperations.symdiff(left_idxs, right_idxs))
    @timeit_debug timer_output "DSL_ncon" begin
        ctx.data[cmd.output_name] = TensorOperations.tensorcontract(
            ctx.data[cmd.left_name], left_idxs,
            ctx.data[cmd.right_name], right_idxs,
            t_symdiff
        )
    @debug "ncon DSL command: output_name=$(cmd.output_name), left_idxs=$(left_idxs), right_idxs=$(right_idxs), contract_indices=$(t_symdiff)"
    end
    nothing
end

"""
    execute!(cmd::ViewCommand, ctx::ExecutionCtx{T}) where {T}

Execute a view DSL command
"""
function execute!(cmd::ViewCommand, ctx::QXContext{T}) where {T}
    @timeit_debug timer_output "DSL_view" begin
        dims = size(ctx.data[cmd.target])
        view_index_list = [i == cmd.bond_index ? cmd.bond_range : UnitRange(1, dims[i]) for i in 1:length(dims)]
        ctx.data[cmd.name] = @view ctx.data[cmd.target][view_index_list...]
    @debug "view DSL command: name=$(cmd.name), target=$(cmd.target), dims=$(dims)"
    end
    nothing
end


###############################################################################
# Execution functions
###############################################################################

"""
    reduce_nodes(nodes::Dict{Symbol, Vector{T}})

Recombine slices results
"""
function reduce_nodes(nodes::AbstractDict{Symbol, Vector{T}}) where {T}
    sum(reduce((x,y) -> x .* y, values(nodes)))
end

"""
    execute!(ctx::QXContext{T}) where T

Run a given context.
"""
function execute!(ctx::QXContext{T}) where T
    results = Dict{String, eltype(T)}([k => 0 for k in ctx.params.amplitudes])

    input_file = JLD.jldopen(ctx.input_file, "r")

    split_idx = findfirst(x -> !(x isa LoadCommand) && !(x isa ParametricCommand{LoadCommand}), ctx.cmds)
    # static I/O commands do not depends on any substitutions and can be run
    # once for all combinations of output qubits and slices
    static_iocmds, parametric_iocmds = begin
        iocmds = ctx.cmds[1:split_idx-1]
        pred = x -> x isa LoadCommand
        filter(pred, iocmds), filter(!pred, iocmds)
    end
    cmds = ctx.cmds[split_idx:end] 

    length(parametric_iocmds) != 0 && error("parametric io commands currently unsupported")

    # Figure out the names of the tensors being loaded by iocmds
    statically_loaded_tensors = [x.name for x in static_iocmds]
    # Remove any delete commands that delete tensors just loaded
    filter!(x -> !(x isa DeleteCommand && x.label in statically_loaded_tensors), cmds)

    # Remove parametric delete commmands that will delete output tensors
    filter!(x -> !(x isa ParametricCommand{DeleteCommand} && startswith(x.args, "\$o")), cmds)

    #FIXME: I also don't think this is necessary anymore
    #FIXME: This is not nice - shouldn't be exposing the ParametricCommand implementation
    parametrically_loaded_tensors = [split(x.args, " ")[1] for x in parametric_iocmds]
    # Remove any delete commands that delete tensors just loaded
    filter!(x -> !(x isa ParametricCommand{DeleteCommand} && x.args in parametrically_loaded_tensors), cmds)

    for iocmd in static_iocmds
        ctx.data[iocmd.name] = read(input_file, String(iocmd.label))
    end

    # run command substitution
    for substitution_set in ctx.params
        for substitution in substitution_set
            subbed_cmds = apply_substitution(cmds, substitution)

            # Run each of the DSL commands in order
            for cmd in subbed_cmds
                #TODO: Without checkpointing, etc. the SaveCommand *should* be the last command
                #      so its execution can probably be pulled out of this loop
                if cmd isa SaveCommand
                    # The data, `ctx.data[cmd.name]`, needs to be dereferenced with `[]`
                    # Although it's a scalar, it will be within an N-d array
                    results[substitution_set.amplitude] += ctx.data[cmd.name][]
                else
                    #TODO: This could be moved out of the conditional entirely
                    #      but the symbol we're saving as would need to be updated to prevent overwrites
                    execute!(cmd, ctx)
                end
            end
        end
    end

    close(input_file)

    if haskey(ENV, "QXRUN_TIMER")
        io = IOBuffer();
        print_timer(io, timer_output)
        op = String(take!(io))
        @info "Timed calls:\n$(op)\n"
    end

    #TODO: These results could also be written to `ctx.output_file`
    return results
end


"""
    execute(dsl_file::String, param_file::String, input_file::String, output_file::String)

Run the commands in dsl_file, parameterised by the contents of param_file, with inputs
specified in input_file, and save the output(s) to output_file.
"""
function execute(dsl_file::String, param_file::String, input_file::String, output_file::String)
    if output_file == ""
        output_file = input_file
    end

    commands = parse_dsl(dsl_file)
    params = Parameters(param_file)

    ctx = QXContext(commands, params, input_file, output_file)

    results = execute!(ctx)

    JLD.save(output_file, "results", results)

    return results
end


end