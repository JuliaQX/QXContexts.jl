export SliceIterator

using QXContexts.ComputeGraphs
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
    SliceIterator(cg::ComputeGraph, args..., num_bonds=nothing)

Constructor to initialise instance from compute graph object. Optional num_bonds argument
allows number of bonds used to be limited.
"""
function SliceIterator(cg::ComputeGraph, args...; max_slices=nothing)
    slice_params = params(cg, ViewCommand)
    num_slices = (max_slices === nothing) ? length(slice_params) : min(max_slices, length(slice_params))
    dims = map(x -> slice_params[Symbol("v$(x)")], 1:num_slices)
    SliceIterator(dims, args...)
end

"""Implement required iterator interface functions"""

Base.iterate(a::SliceIterator) = length(a) == 0 ? nothing : (Int[Tuple(a.iter[a.start])...], a.start)
Base.iterate(a::SliceIterator, state) = length(a) <= (state + 1 - a.start) ? nothing : (Int[Tuple(a.iter[state + 1])...], state + 1)
Base.length(a::SliceIterator) = a.stop - a.start + 1
Base.eltype(::SliceIterator) = Vector{Int}
Base.getindex(a::SliceIterator, i...) = collect(Tuple(a.iter[i...]))