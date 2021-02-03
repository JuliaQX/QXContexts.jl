export AbstractCommand
export CommandList
# Standard Commands
export LoadCommand, SaveCommand, DeleteCommand, ReshapeCommand, PermuteCommand
export NconCommand, ViewCommand
# Functions
export apply_substitution, apply_substitution!
export parse_dsl

"""
Abstract base type for all DSL commands

    Current spec:

    Load tensor:      load <name:str> <hdf5_label:str>
    Save tensor:      save <name:str> <hdf5_label:str>
    Delete tensor:    del <name:str>
    Reshape tensor:   reshape <name:str> <shape:list>
    Permute tensor:   permute <name:str> <shape:list>
    Contract tensors: ncon <output_name:str> <left_name:str> <left_idxs:list> <right_name:str> <right_idxs:list>
    View tensor:      view <name:str> <target:str> <bond_idx:Int> <bond_range:list>
"""
abstract type AbstractCommand end

"Abstract base type for parametric DSL commands"
struct ParametricCommand{T <: AbstractCommand} <: AbstractCommand
    args::String
end

"Type alias for an array of DSL commands"
const CommandList = Vector{AbstractCommand}

###############################################################################
# Command Types
###############################################################################

"""
    LoadCommand(name::String, label::String)

Represents a command to load a tensor

Example
=======
load node_1 node_1
"""
struct LoadCommand <: AbstractCommand
    name::Symbol
    label::Symbol
end

LoadCommand(name::String, label::String) = LoadCommand(Symbol(name), Symbol(label))


"""
    SaveCommand(name::String, label::String, filename::String)

Represents a command to save a tensor

Example
=======
save node_1 result
"""
struct SaveCommand <: AbstractCommand
    name::Symbol
    label::Symbol
end

SaveCommand(name::String, label::String) = SaveCommand(Symbol(name), Symbol(label))


"""
    DeleteCommand(name::String)

Represents a command to delete a tensor from memory, freeing resources

Example
=======
del node_1
"""
struct DeleteCommand <: AbstractCommand
    label::Symbol
end

DeleteCommand(name::String) = DeleteCommand(Symbol(name))


"""
    ReshapeCommand(name::String, dims_list::String)

Represents a command to reshape a tensor

Example
=======
reshape node_1 4,1
"""
struct ReshapeCommand <: AbstractCommand
    name::Symbol
    dims::Vector{Vector{Int}}
end

function ReshapeCommand(name::String, dims_list::String)
    dims = [parse.(Int, split(x, ",")) for x in split(dims_list, ";")]
    ReshapeCommand(Symbol(name), dims)
end


"""
    PermuteCommand(name::String, dims::String)

Represents a command to permute a tensor

Example
=======
permute node_1 2,1
"""
struct PermuteCommand <: AbstractCommand
    name::Symbol
    dims::Vector{Int}
end

PermuteCommand(name::String, dims::String) = PermuteCommand(Symbol(name), parse.(Int, split(dims, ",")))


"""
    NconCommand(output_name::String,
                left_name::String, left_idxs::String,
                right_name::String, right_idxs::String)

Represents a command to contract two tensors

Example
=======
ncon node_23 node_22 1,-1 node_10 1
"""
struct NconCommand <: AbstractCommand
    output_name::Symbol
    left_name::Symbol
    left_idxs::Vector{Int}
    right_name::Symbol
    right_idxs::Vector{Int}
end

function NconCommand(output_name::String,
                        left_name::String, left_idxs::String,
                        right_name::String, right_idxs::String)
    left_idxs = parse.(Int, split(left_idxs, ","))
    right_idxs = parse.(Int, split(right_idxs, ","))

    if left_idxs == [0] pop!(left_idxs) end
    if right_idxs == [0] pop!(right_idxs) end

    NconCommand(Symbol(output_name),
                Symbol(left_name), left_idxs,
                Symbol(right_name), right_idxs)
end


"""
    ViewCommand(name::String, target::String, bond_index::String, bond_range::String)

Represents a command to 

Example
=======
view node_2 node_1 1 1
"""
struct ViewCommand <: AbstractCommand
    name::Symbol
    target::Symbol
    bond_index::Int
    bond_range::Vector{Int}
end

function ViewCommand(name::String, target::String, bond_index::String, bond_range::String)
    ViewCommand(Symbol(name), Symbol(target), parse(Int, bond_index), parse.(Int, split(bond_range, ",")))
end


###############################################################################
# Parametric DSL substitution functions
###############################################################################

"Type alias for the representation of parametric DSL substitutions"
const SubstitutionType = Dict{Symbol, String}

"Regular Expression to find variable tokens within a parametric DSL command"
const ParametricVariableNameRegex = r"(\$[^\s,]+)"

apply_substitution(command::AbstractCommand, _::SubstitutionType) = command

"""
    apply_substitution(command::ParametricCommand{T}, substitutions::SubstitutionType) where T <: AbstractCommand

Find and replace all parameters in a parametric DSL command with the corresponding substitution.
Will return the appropriate command type; e.g. passing a ParametricCommand{LoadCommand} will return a LoadCommand.
"""
function apply_substitution(command::ParametricCommand{T}, substitutions::SubstitutionType) where T <: AbstractCommand
    args = replace(command.args, ParametricVariableNameRegex => x -> substitutions[Symbol(x)])
    return T(string.(split(args, " "))...)
end

"""
    apply_substitution!(commands::CommandList, substitutions::SubstitutionType)

Apply substitutions to all parametric commands in command list
"""
function apply_substitution!(commands::CommandList, substitutions::SubstitutionType)
    replace!(cmd -> apply_substitution(cmd, substitutions), commands)
end

"""
    apply_substitution(commands::CommandList, substitutions::SubstitutionType)

Non-destructively apply substitutions to all parametric commands in command list
"""
function apply_substitution(commands::CommandList, substitutions::SubstitutionType)
    commands_copy = copy(commands)
    apply_substitution!(commands_copy, substitutions)
    return commands_copy
end


###############################################################################
# DSL Parsing functions
###############################################################################

"""
    parse_dsl(buffer::Vector{String})

Parse a list of DSL commands and generate a CommandList for execution
"""
function parse_dsl(buffer::Vector{String})
    commands = CommandList()

    command_types = Base.ImmutableDict(
        "load"    => LoadCommand,
        "save"    => SaveCommand,
        "del"     => DeleteCommand,
        "reshape" => ReshapeCommand,
        "permute" => PermuteCommand,
        "ncon"    => NconCommand,
        "view"    => ViewCommand,
    )

    for line in buffer
        if any(!isascii, line)
            # This may not be an issue but err on the side of caution for now
            error("Unsupported non-ASCII character encountered in DSL:\n\t'$line'")
        end

        type, args = string.(split(line, " "; limit = 2))

        if occursin("\$", line)
            #command = parametric_command_types[type](args)
            command = ParametricCommand{command_types[type]}(args)
        else
            args = string.(split(args, " "))
            command = command_types[type](args...)
        end

        push!(commands, command)
    end

    return commands
end

"""
    parse_dsl(filename::String)

Read a DSL file and generate a CommandList for execution
"""
function parse_dsl(filename::String)
    return open(filename) do file
        parse_dsl(readlines(file))
    end
end