using YAML
using DataStructures
using FileIO

# Functions for parsing and writing dsl files
export parse_dsl, parse_dsl_files, generate_dsl_files

# Define compatible DSL file version number, which must match when parsed.
const DSL_VERSION = VersionNumber("0.4.0")

###############################################################################
# DSL Parsing functions
###############################################################################
"""
    write_version_header(io::IO)

Function to write version head to DSL file with current version constant
"""
function write_version_header(io::IO)
    write(io, "# version: $(DSL_VERSION)\n")
end

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
        is_compatible = version_dsl == DSL_VERSION
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
function parse_command(line::AbstractString)
    m = match(r"^([a-z]*)", line)
    command = nothing
    if m !== nothing
        type = m.captures[1]
        command = if type == "load" LoadCommand(line)
        elseif type == "view" command = ViewCommand(line)
        elseif type == "ncon" command = ContractCommand(line)
        elseif type == "save" command = SaveCommand(line)
        elseif type == "output" command = OutputCommand(line)
        elseif type == "reshape" command = ReshapeCommand(line)
        else
            error("$(type) command has not been implemented yet")
        end
    end
    command
end

"""
    parse_dsl(buffer::Vector{String})

Parse a list of DSL commands and generate a CommandList for execution
"""
function parse_dsl(buffer::Vector{<:AbstractString})
    line = string(strip(first(buffer)))
    is_compatible, version_dsl = check_compatible_version_dsl(line)
    if !is_compatible
        throw(ArgumentError("DSL version not compatible:\n\t'$version_dsl', expected '$DSL_VERSION'"))
    end

    # find index of first line that doesn't start with "#"
    cmd_idx = findfirst(x -> x[1] != '#', buffer)
    metadata_str = join(map(x -> replace(x, r"^# " => ""), buffer[2:cmd_idx-1]), "\n")
    metadata = length(metadata_str) > 0 ? YAML.load(metadata_str) : OrderedDict()

    cmds = Vector{AbstractCommand}()
    for line in buffer[cmd_idx:end]
        line_command = string(first(split(line, '#')))
        if !isempty(line_command)
            push!(cmds, parse_command(line_command))
        end
    end
    build_tree(cmds), metadata
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

"""
    parse_dsl_files(dsl_file::String, data_file::String)

Read a DSL file and tensors file and return compute tree and meta data
"""
function parse_dsl_files(dsl_file::String, data_file::String)
    root_node, metadata = parse_dsl(dsl_file)
    tensors = Dict(Symbol(x) => y for (x, y) in pairs(load(data_file)))
    ComputeGraph(root_node, tensors), metadata
end

###############################################################################
# DSL writing functions
###############################################################################

"""
    Base.write(io::IO, Union{ComputeNode, ComputeGraph}; metadata=nothing)

Write the compute tree to an ascii file. Optionally write meta_data
if present
"""
function Base.write(io::IO, cn::ComputeNode; metadata=nothing)
    # first we write the version header
    write_version_header(io)

    if metadata !== nothing
        # prepend each link of yaml output with "# "
        yml_str = YAML.write(metadata)
        yml_str = join(["# " * x for x in split(yml_str, "\n")], "\n") * "\n"
        write(io, yml_str)
    end

    for each in PostOrderDFS(cn)
        write(io, each.op)
    end
end

"""
    generate_dsl_files(compute_tree::ComputeGraph,
                       prefix::String;
                       force::Bool=true,
                       metadata=nothing)

Function to create dsl and data files to contract the given tensor network circuit
with the plan provided
"""
function generate_dsl_files(compute_tree::ComputeGraph,
                            prefix::String;
                            force::Bool=true,
                            metadata=nothing)

    dsl_filename = "$(prefix).qx"
    data_filename = "$(prefix).jld2"

    @assert force || !isfile(dsl_filename) "Error $(dsl_filename) already exists"
    @assert force || !isfile(data_filename) "Error $(data_filename) already exists"

    open(dsl_filename, "w") do dsl_io
        write(dsl_io, compute_tree.root; metadata=metadata)
    end

    save(data_filename, Dict(String(x) => y for (x, y) in pairs(compute_tree.tensors)))
    nothing
end