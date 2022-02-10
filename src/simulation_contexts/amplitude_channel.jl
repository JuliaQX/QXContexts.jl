#=
This file defines an implementation of AbstractChannel called an AmplitudeChannel.

This channel is intended to collect sliced probability amplitudes a produce output
full amplitudes to be used in rejection sampling. The sliced amplitudes are stored
and accumulated in an array along with a set of cartesian indices indicating which
slices have been accumulated. Once all slices of an amplitude are collected, the
wait conditions are notified to indicate the channel is ready to be taken from.
=#
using DataStructures: PriorityQueue

import Base: put!, wait, isready, take!, fetch

#===================================================#
# Channel Data Structure
#===================================================#

mutable struct AmplitudeChannel{V} <: AbstractChannel{V}
    mod_cond::Threads.Condition
    take_cond::Threads.Condition
    state::Symbol
    excp::Union{Exception, Nothing}

    queue::PriorityQueue{Int, Int}
    amps::Vector{V}
    slices::Vector{Set{CartesianIndex}}
    bitstrings::Vector{Union{Nothing, Vector{Bool}}}
    num_slices::Int
end

function AmplitudeChannel{V}(num_slices::Integer, size::Integer=32) where V
    lock = ReentrantLock()
    mod_cond, take_cond = Threads.Condition(lock), Threads.Condition(lock)
    AmplitudeChannel{V}(
                        mod_cond,
                        take_cond,
                        :open,
                        nothing,
                        PriorityQueue{Int, Int}(Base.Order.Reverse, 1:size .=> zeros(Int, size)), 
                        zeros(V, size),
                        [Set{CartesianIndex}() for _ in 1:size],
                        fill(nothing, size),
                        num_slices
                        )
end

#===================================================#
# Channel Interface
#===================================================#
"""Store and accumulate the given amplitude in the channel"""
function put!(c::AmplitudeChannel{V}, bitstring::Vector{Bool}, slice::CartesianIndex, amp::V) where V
    lock(c.mod_cond)
    try
        inds = get_inds(c, bitstring)

        result_add = false
        ind = 0
        for i in 1:length(inds)
            ind = inds[i]
            if !(slice in c.slices[ind])
                c.queue[ind] += 1
                c.amps[ind] += amp
                c.bitstrings[ind] === nothing && (c.bitstrings[ind] = bitstring)
                push!(c.slices[ind], slice)
                result_add = true
                break
            end
        end

        !result_add && (ind = expand!(c, bitstring, slice, amp))
        length(c.slices[ind]) == c.num_slices && notify(c.take_cond; all=false)
    finally
        unlock(c.mod_cond)
    end
end

"""Take an amplitude from the chanel"""
function take!(c::AmplitudeChannel)
    lock(c.mod_cond)
    try
        while !isready(c)
            wait(c.take_cond)
	    end
        bitstring, amp, ind = fetch(c)
        c.queue[ind] = 0
        c.amps[ind] = 0
        c.bitstrings[ind] = nothing
        c.slices[ind] = Set{CartesianIndex}()
	    return bitstring, amp
    finally
        unlock(c.mod_cond)
    end
end

"""Expand the size of the channel to store the given amplitude"""
function expand!(c, bitstring, slice, amp)
    append!(c.bitstrings, [bitstring])
    append!(c.slices, [Set{CartesianIndex}([slice])])
    append!(c.amps, [amp])
    ind = length(c.amps)
    c.queue[ind] = 1
    ind
end

function fetch(c::AmplitudeChannel)
    ind = peek(c.queue)[1]
    c.bitstrings[ind], c.amps[ind], ind
end

isready(c::AmplitudeChannel) = peek(c.queue)[2] == c.num_slices
get_inds(c, bitstring) = [findall(b -> b == bitstring, c.bitstrings); findall(b -> b == nothing, c.bitstrings)]