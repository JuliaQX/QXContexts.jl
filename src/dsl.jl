module DSL

# Types
export AbstractCommand
export CommandList
# export ParametricCommand
# export SubstitutionType

# Standard Commands
export LoadCommand, SaveCommand, DeleteCommand, ReshapeCommand, PermuteCommand
export NconCommand, ViewCommand, OutputsCommand

# Functions
# export apply_substitution, apply_substitution!
export parse_dsl

# Define compatible DSL file version number, which must match when parsed.
const VERSION_DSL = VersionNumber("0.3.0")

"""
Abstract base type for all DSL commands

    Current spec:

Generate loads:   outputs <num:str>
Load tensor:      load <name:str> <hdf5_label:str>
Save tensor:      save <name:str> <hdf5_label:str>
Reshape tensor:   reshape <name:str> <shape:list>
Permute tensor:   permute <name:str> <shape:list>
Contract tensors: ncon <output_name:str> <output_idxs:list> <left_name:str> <left_idxs:list> <right_name:str> <right_idxs:list>
View tensor:      view <name:str> <target:str> <bond_idx:Int> <bond_range:list>
"""
abstract type AbstractCommand end

# Required for `append` in the `parse_dsl` function
# Base.length(::AbstractCommand) = 1

# Base.iterate(x::T, state::Bool=true) where {T <: AbstractCommand} = state ? (x, false) : nothing

# "Abstract base type for parametric DSL commands"
# struct ParametricCommand{T <: AbstractCommand} <: AbstractCommand
#     args::String
# end

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
`load node_1 node_1`
"""
struct LoadCommand <: AbstractCommand
    name::Symbol
    label::Symbol
end

LoadCommand(name::AbstractString, label::AbstractString) = LoadCommand(Symbol(name), Symbol(label))


"""
    SaveCommand(name::AbstractString, label::AbstractString, filename::AbstractString)

Represents a command to save a tensor

Example
=======
`save node_1 result`
"""
struct SaveCommand <: AbstractCommand
    name::Symbol
    label::Symbol
end

SaveCommand(name::AbstractString, label::AbstractString) = SaveCommand(Symbol(name), Symbol(label))

"""
    ReshapeCommand(name::AbstractString, dims_list::AbstractString)

Represents a command to reshape a tensor

Example
=======
`reshape node_1 4,1`
"""
struct ReshapeCommand <: AbstractCommand
    name::Symbol
    dims::Vector{Vector{Int}}
end

function ReshapeCommand(name::AbstractString, dims_list::AbstractString)
    dims = [parse.(Int, split(x, ",")) for x in split(dims_list, ";")]
    ReshapeCommand(Symbol(name), dims)
end


"""
    PermuteCommand(name::AbstractString, dims::AbstractString)

Represents a command to permute a tensor

Example
=======
`permute node_1 2,1`
"""
struct PermuteCommand <: AbstractCommand
    name::Symbol
    dims::Vector{Int}
end

PermuteCommand(name::AbstractString, dims::AbstractString) = PermuteCommand(Symbol(name), parse.(Int, split(dims, ",")))


"""
    NconCommand(output_name::String, output_idxs::String
                left_name::String, left_idxs::String,
                right_name::String, right_idxs::String)

Represents a command to contract two tensors

Example
=======
`ncon node_23 1 node_22 2,1 node_10 2`
"""
struct NconCommand <: AbstractCommand
    output_name::Symbol
    output_idxs::Vector{Int}
    left_name::Symbol
    left_idxs::Vector{Int}
    right_name::Symbol
    right_idxs::Vector{Int}
end

function NconCommand(output_name::AbstractString, output_idxs::AbstractString,
                     left_name::AbstractString, left_idxs::AbstractString,
                     right_name::AbstractString, right_idxs::AbstractString)
    parse_idxs = x -> [y for y in parse.(Int, split(x, ",")) if y != 0]

    NconCommand(Symbol(output_name), parse_idxs(output_idxs),
                Symbol(left_name), parse_idxs(left_idxs),
                Symbol(right_name), parse_idxs(right_idxs))
end

"""
    ViewCommand(name::String, target::String, bond_index::String, bond_range::String)

Represents a command to

Example
=======
`view node_2 node_1 1 1`
"""
struct ViewCommand <: AbstractCommand
    name::Symbol
    target::Symbol
    bond_index::Int
    bond_range::Symbol
end

function ViewCommand(name::AbstractString, target::AbstractString, bond_index::AbstractString, bond_range::AbstractString)
    ViewCommand(Symbol(name), Symbol(target), parse(Int, bond_index), Symbol(bond_range))
end

"""
    OutputsCommand(num_outputs::String)

Tells how many outputs to expect

Example
=======
`outputs 3`
```
"""
struct OutputsCommand <: AbstractCommand
    num_outputs::Int64
end

function OutputsCommand(num_outputs::AbstractString)
    OutputsCommand(parse(Int, num_outputs))
end


# ###############################################################################
# # Parametric DSL substitution functions
# ###############################################################################

# "Type alias for the representation of parametric DSL substitutions"
# const SubstitutionType = Dict{Symbol, String}

# "Regular Expression to find variable tokens within a parametric DSL command"
# const ParametricVariableNameRegex = r"(\$[^\s,_]+)"

# apply_substitution(command::AbstractCommand, ::SubstitutionType) = command

# """
#     apply_substitution(command::ParametricCommand{T}, substitutions::SubstitutionType) where T <: AbstractCommand

# Find and replace all parameters in a parametric DSL command with the corresponding substitution.
# Will return the appropriate command type; e.g. passing a ParametricCommand{LoadCommand} will return a LoadCommand.
# """
# function apply_substitution(command::ParametricCommand{T},
#                             substitutions::SubstitutionType) where T <: AbstractCommand
#     args = replace(command.args, ParametricVariableNameRegex => x -> get(substitutions, Symbol(x), "*"))
#     return T(string.(split(args, " "))...)
# end

# """
#     apply_substitution!(commands::CommandList, substitutions::SubstitutionType)

# Apply substitutions to all parametric commands in command list
# """
# function apply_substitution!(commands::CommandList, substitutions::SubstitutionType)
#     replace!(cmd -> apply_substitution(cmd, substitutions), commands)
# end

# """
#     apply_substitution(commands::CommandList, substitutions::SubstitutionType)

# Non-destructively apply substitutions to all parametric commands in command list
# """
# function apply_substitution(commands::CommandList, substitutions::SubstitutionType)
#     commands_copy = copy(commands)
#     apply_substitution!(commands_copy, substitutions)
#     return commands_copy
# end


###############################################################################
# DSL Parsing functions
###############################################################################

"""
    check_compatible_version_dsl(line::String)

Checks if version is defined in line and checks compatibility with VERSION_DSL
"""
function check_compatible_version_dsl(line::String)
    exists_version_dsl = startswith(strip(line), '#') && occursin("version:", line)
    is_compatible::Bool = true

    if exists_version_dsl
        version_dsl = strip(last(split(line,"version:")))
        version_dsl = VersionNumber(version_dsl)

        # Simple logic enforcing matching versions, which can be extended
        is_compatible = version_dsl == VERSION_DSL
    else
        is_compatible = false
        version_dsl = nothing
    end

    return is_compatible, version_dsl
end

"""
    parse_command(line::String)

Parse a DSL command
"""
function parse_command(line::String)
    if any(!isascii, line)
        # This may not be an issue but err on the side of caution for now
        throw(ArgumentError("Non-ascii DSL commands not supported:\n\t'$line'"))
    end

    type, args... = split(line)
    args = string.(args)

    if type == "load" command = LoadCommand(args...)
    elseif type == "view" command = ViewCommand(args...)
    elseif type == "ncon" command = NconCommand(args...)
    elseif type == "save" command = SaveCommand(args...)
    elseif type == "outputs" command = OutputsCommand(args...)
    # elseif type == "reshape" command = ReshapeCommand(args...)
    # elseif type == "permute" command = PermuteCommand(args...)
    else
        error("$(type) command has not been implemented yet")
    end

    return command
end

"""
    parse_dsl(buffer::Vector{String})

Parse a list of DSL commands and generate a CommandList for execution
"""
function parse_dsl(buffer::Vector{String})
    commands = CommandList()

    line = string(strip(first(buffer)))
    is_compatible, version_dsl = check_compatible_version_dsl(line)
    if !is_compatible
        throw(ArgumentError("DSL version not compatible:\n\t'$version_dsl', expected '$VERSION_DSL'"))
    end

    for line in buffer
        line_command = string(first(split(line, '#')))
        if !isempty(line_command)
            command = parse_command(line_command)
            push!(commands, command)
        end
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

end