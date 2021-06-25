using AbstractTrees
using YAML

export build_tree, ComputeNode, ComputeGraph, get_commands, params
# In this file we define a tree data structure which can be used for optimisation passes
# over contraction commands

"""Generic tree node data structure"""
mutable struct ComputeNode{T}
    op::Union{Nothing, T}
    children::Vector{ComputeNode}
    parent::ComputeNode
    # Root constructor
    ComputeNode{T}(data) where T = new{T}(data, ComputeNode[])
    ComputeNode{T}() where T = new{T}(nothing, ComputeNode[])
    # Child node constructor
    ComputeNode{T}(data, parent::ComputeNode{U}) where {T, U} = new{T}(data, ComputeNode[], parent)
end
ComputeNode(op) = ComputeNode{typeof(op)}(op)

"""Represent a compute graph with root node and initial tensors"""
struct ComputeGraph
    root::ComputeNode
    tensors::Dict{Symbol, AbstractArray}
end

"""
    get_commands(ct::ComputeNode, type::Type=Any; by=nothing, iterf=PostOrderDFS)

Utility function that retrieves a list of commands if given type and sorted according to the
provided criteria. By default they are returned in the order returned by depth first traversal
which returns leaves before parents.
"""
function get_commands(cn::ComputeNode, type::Type=Any; by=nothing, iterf=PostOrderDFS)
    cmds = map(x -> x.op, filter(x -> x.op isa type, collect(iterf(cn))))
    if by !== nothing
        sort!(cmds, by=by)
    end
    cmds
end

"""Implement for ComputeGraph also"""
get_commands(cg::ComputeGraph, args...; kwargs...) = get_commands(cg.root, args...; kwargs...)

"""
    AbstractTrees.children(node::ComputeNode)

Implement children function from AbstractTrees package
"""
function AbstractTrees.children(node::ComputeNode)
    Tuple(node.children)
end

"""
    params(node::ComputeNode, optype::Type=Any)

Compile all parameters from this and descendents with optional op type qualifier.
This can be used to return only output or view parameters with

params(node, OutputCommand)

or

params(node, ViewCommand)
"""
function params(node::ComputeNode, optype::Type=Any)
    local_params = node.op isa optype ? params(node.op) : Dict{Symbol, Int}()
    merge!(local_params, params.(node.children, [optype])...)
end

params(cg::ComputeGraph, args...) = params(cg.root, args...)
output(node::ComputeNode) = output(node.op)
output(cg::ComputeGraph) = output(cg.root)

###########################################################################
# Functions and data structures for trees of contraction commands
###########################################################################

"""
    build_tree(cmds::Vector{<: AbstractCommand})

Function to construct a tree from a list of commands
"""
function build_tree(cmds::Vector{<: AbstractCommand})
    nodes = Dict{Symbol, ComputeNode}()

    for op in cmds
        node = ComputeNode(op)
        for input in inputs(op)
            if haskey(nodes, input)
                push!(node.children, nodes[input])
                nodes[input].parent = node
            end
        end
        nodes[output(op)] = node
    end
    parentless = collect(keys(filter(x -> !isdefined(x[2], :parent), nodes)))
    @assert length(parentless) == 1 "Only root node should have no parent"
    root = parentless[1]
    nodes[root]
end