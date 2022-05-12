#=
This file defines functions for computing various metrics for a compute graph.
    
These include:
    - the maximum degree of a tensor produced by any of the commands in the graph.
    - the depth of the compute graph.
    - the length (or number of nodes) in the compute graph.
    - how balanced the graph is.
    - The time and space (number of floating point operations and number of tensor elements to store)
      requirements of a contraction as a function of time step (dsl line number).
=#
export costs, max_degree, depth, balance

indices(c::ContractCommand) = c.left_idxs, c.right_idxs, c.output_idxs

max_degree(c::ContractCommand) = maximum(length.(indices(c)))
max_degree(n::ComputeNode) = maximum(max_degree.(children(n)), init=0)
max_degree(n::ComputeNode{ContractCommand}) = maximum([max_degree(n.op), max_degree.(children(n))...])
depth(n::ComputeNode) = 1 + maximum(depth.(children(n)), init=0)
Base.length(n::ComputeNode) = 1 + sum(length.(children(n)), init=0)
balance(n::ComputeNode) = ceil(log2(length(n)))/depth(n)

"""
    costs(cg::ComputeGraph, params::Dict{Symbol, Int}=Dict{Symbol, Int}())

Compute the time and space costs of executing the given computation graph `cg`. 
Slice variables in the graph are set according to the given `params` dict.

Returns two arrays containing the number of operations and memory footprint
during contraction respectively.
"""
function costs(cg::ComputeGraph, params::Dict{Symbol, Int}=Dict{Symbol, Int}())
    op_counts, memory_footprint, _ = costs(cg.root, params)
    (op_counts, memory_footprint) .|> cumsum
end

function costs(cn::ComputeNode, params::Dict{Symbol, Int})
    op_counts, memory_footprint, dims = Int[], Int[], Vector{Int}[]
    for child in children(cn)
        a, b, c = costs(child, params)
        op_counts = vcat(op_counts, a)
        memory_footprint = vcat(memory_footprint, b)
        push!(dims, c)
    end

    op_count, footprint_change, dims = costs(cn.op, params, dims)
    Int[op_counts; op_count], Int[memory_footprint; footprint_change], dims
end

# Function methods to compute contributions to the cost from various dsl commands.
# For each dsl command, the corresponding implementation of costs is expected to
# return a Tuple{Int, Int, Vector{Int}} containing, respectively, the number of operations 
# performed by the command, the change in the number of elements stored in memory after the 
# command is finished and a vector containing the dimensions of the indices of the output 
# tensor (used for propagating the dimensions of indices, through the graph, from the leaf nodes).

costs(cmd::AbstractCommand, params, dims) = ([], [], dims[1])
costs(cmd::LoadCommand, params, dims)     = (0, prod(cmd.dims), cmd.dims)
costs(cmd::OutputCommand, params, dims)   = (0, cmd.dim, [cmd.dim])
costs(cmd::ReshapeCommand, params, dims)  = ([], [], [prod(dims[1][inds]) for inds in cmd.dims])

function costs(cmd::ViewCommand, params, dims)
    dims = dims[1]
    if haskey(params, cmd.slice_sym)
        new_dims = copy(dims); new_dims[cmd.bond_index] = 1
        return (0, prod(new_dims) - prod(dims), new_dims)
    end
    ([], [], dims)
end

function costs(cmd::ContractCommand, params, dims)
    a, b, c = indices(cmd)
    a_dims, b_dims = dims
    dims = Dict{Int, Int}([a .=> a_dims; b .=> b_dims])

    batched_idxs = intersect(a, b, c)
    a = setdiff(a, batched_idxs)
    b = setdiff(b, batched_idxs)
    common = intersect(a, b)
    remaining = symdiff(a, b)

    op_count = prod(i -> dims[i], [common; remaining; batched_idxs]; init=1)
    footprint_change = prod(i -> dims[i], c; init=1) - prod(a_dims) - prod(b_dims)
    op_count, footprint_change, [dims[i] for i in c]
end

"""Implement show for compute node to display some useful metrics"""
function Base.show(io::IO, c::ComputeNode{T}) where T
    print(io, "ComputeNode{$(T)}: children: $(length(c)-1), ",
              "depth: $(depth(c)), balance: $(balance(c)), ",
              "max_degree: $(max_degree(c))")
end