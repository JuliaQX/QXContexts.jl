export AbstractCommand, CommandList, params, inputs, output
export ContractCommand, LoadCommand, OutputCommand, SaveCommand, ReshapeCommand, ViewCommand

"""
We define structs for each command type with each implementing the interface

NameCommand(s::AbstractString): a constructor that initiates and instance from a str representation
write(io::IO, c::NameCommand): serialises to given io object
output(c::NameCommand): gives symbol of output from command
inputs(c::NameCommand): gives vector of inputs
params(c::NameCommand): dictionary of parameter symbols and dimensions

The command struct itself is callable with a default implementation which expects appropriate inputs
as arguments.

Summary of command and string format of each

Contract tensors: ncon <output_name:str> <output_idxs:list> <left_name:str> <left_idxs:list> <right_name:str> <right_idxs:list>
Load tensor:      load <name:str> <label:str> <dims:list>
Save tensor:      save <name:str> <label:str>
Reshape tensor:   reshape <output:str> <input:str> <shape:list>
View tensor:      view <name:str> <target:str> <slice_symbol:str> <bond_idx:Int> <bond_dim:Int>
Output:           output <name:str> <idx:int> <dim:int>
"""

abstract type AbstractCommand end

params(::AbstractCommand) = Dict{Symbol, Int}()

CommandList = Vector{AbstractCommand}

"""Regex to match symbols"""
const sym_fmt = "[A-Z|a-z|0-9|_]*"

"""Structure to represent a contraction command"""
mutable struct ContractCommand <: AbstractCommand
    output_name::Symbol
    output_idxs::Vector{Int}
    left_name::Symbol
    left_idxs::Vector{Int}
    right_name::Symbol
    right_idxs::Vector{Int}
end

"""
    ContractCommand(s::AbstractString)

Constructor which reads command from a string
"""
function ContractCommand(s::AbstractString)
    p = match(Regex("ncon" * repeat(" ($sym_fmt) ([0-9|,]*)", 3)), s)
    @assert p !== nothing "Command must begin with \"ncon\""
    s = x -> Symbol(x)
    l = x -> x == "0" ? Int[] : map(y -> parse(Int, y), split(x, ","))
    ContractCommand(s(p[1]), l(p[2]), s(p[3]), l(p[4]), s(p[5]), l(p[6]))
end

"""
    Base.write(io::IO, cmd::ContractCommand)

Function to serialise command to the given IO stream
"""
function Base.write(io::IO, cmd::ContractCommand)
    j = x -> length(x) == 0 ? "0" : join(x, ",")
    write(io, "ncon $(cmd.output_name) $(j(cmd.output_idxs)) $(cmd.left_name) $(j(cmd.left_idxs)) $(cmd.right_name) $(j(cmd.right_idxs))\n")
end

output(c::ContractCommand) = c.output_name
inputs(c::ContractCommand) = [c.left_name, c.right_name]

"""Represents a command to load a tensor from storage"""
struct LoadCommand <: AbstractCommand
    name::Symbol
    label::Symbol
    dims::Vector{Int}
end

output(c::LoadCommand) = c.name
inputs(::LoadCommand) = []

"""
    LoadCommand(s::AbstractString)

Constructor to create instance of command from a string
"""
function LoadCommand(s::AbstractString)
    m = match(Regex("^load ($sym_fmt) ($sym_fmt) ([0-9|,]*)"), s)
    @assert m !== nothing "Load command must have format \"load [name_sym] [src_sym] [dims]\""
    dims = parse.([Int], split(m.captures[3], ","))
    LoadCommand(Symbol.(m.captures[1:2])..., dims)
end

"""Function to serialise command to the given IO stream"""
function Base.write(io::IO, cmd::LoadCommand)
    dims = join(cmd.dims, ",")
    write(io, "load $(cmd.name) $(cmd.label) $(dims)\n")
end

"""Command to save a tensor to storage"""
struct SaveCommand <: AbstractCommand
    name::Symbol
    label::Symbol
end

output(c::SaveCommand) = c.name
inputs(c::SaveCommand) = [c.label]

"""
    SaveCommand(s::AbstractString)

Constructor which creates a command instance form a string
"""
function SaveCommand(s::AbstractString)
    m = match(Regex("^save ($sym_fmt) ($sym_fmt)"), s)
    @assert m !== nothing "Save command must have format \"save [name_sym] [src_sym]\""
    SaveCommand(Symbol.(m.captures)...)
end

"""Function to serialise command to the given IO stream"""
Base.write(io::IO, cmd::SaveCommand) = write(io, "save $(cmd.name) $(cmd.label)\n")

"""Represents a command to reshape a tensor"""
struct ReshapeCommand <: AbstractCommand
    output::Symbol
    input::Symbol
    dims::Vector{Vector{Int}}
end

"""
    ReshapeCommand(s::AbstractString)

Constructor to create reshape command from string representation
"""
function ReshapeCommand(s::AbstractString)
    m = match(Regex("^reshape ($sym_fmt) ($sym_fmt) ([0-9|,|;]*)"), s)
    @assert m !== nothing "Reshape command must have format \"reshape [output] [input] [dims]\""
    dims = [parse.(Int, split(x, ",")) for x in split(m.captures[3], ";")]
    ReshapeCommand(Symbol.(m.captures[1:2])..., dims)
end

output(c::ReshapeCommand) = c.output
inputs(c::ReshapeCommand) = [c.input]

function Base.write(io::IO, c::ReshapeCommand)
    dims_str = join(join.(c.dims, [","]), ";")
    write(io, "reshape $(c.output) $(c.input) $(dims_str)\n")
end

"""Struct to represent a view on a tensor"""
struct ViewCommand <: AbstractCommand
    output_sym::Symbol
    input_sym::Symbol
    slice_sym::Symbol
    bond_index::Int
    bond_dim::Int
end

output(c::ViewCommand) = c.output_sym
inputs(c::ViewCommand) = [c.input_sym]
params(c::ViewCommand) = Dict{Symbol, Int}(c.slice_sym => c.bond_dim)

"""
    ViewCommand(s::AbstractString)

Constructor to create view command from string representation
"""
function ViewCommand(s::AbstractString)
    m = match(Regex("^view ($sym_fmt) ($sym_fmt) ($sym_fmt) ([0-9]*) ([0-9]*)"), s)
    @assert m !== nothing "View command must have format \"view [output_sym] [input_sym] [slice_sym) [index] [dim]\""
    ViewCommand(Symbol.(m.captures[1:3])..., parse.([Int], m.captures[4:5])...)
end

function Base.write(io::IO, c::ViewCommand)
    write(io, "view $(c.output_sym) $(c.input_sym) $(c.slice_sym) $(c.bond_index) $(c.bond_dim)\n")
end

"""Commannd to communicate number of outputs"""
struct OutputCommand <: AbstractCommand
    name::Symbol
    idx::Int
    dim::Int
end

output(c::OutputCommand) = c.name
inputs(::OutputCommand) = Symbol[]
params(c::OutputCommand) = Dict{Symbol, Int}(Symbol("o$(c.idx)") => c.dim)

"""
    OutputCommand(s::AbstractString)

Constructor to create instance of command from string
"""
function OutputCommand(s::AbstractString)
    m = match(Regex("^output ($sym_fmt) ([0-9]*) ([0-9]*)"), s)
    @assert m !== nothing "Output command must have format \"output [name] [idx] [dim]\""
    OutputCommand(Symbol(m.captures[1]), parse.([Int], m.captures[2:3])...)
end

"""Function to serialise command to a string"""
Base.write(io::IO, c::OutputCommand) = write(io, "output $(c.name) $(c.idx) $(c.dim)\n")