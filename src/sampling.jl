module Sampling

export ListSampler #, RejectionSampler, UniformSampler
export create_sampler

using Random
using DataStructures

using QXContexts.Contexts

# Module containing sampler objects which provide different levels of sampling features.
# Each sampler has a constructor which takes a context to perform sampling in and a set
# of keyword arguments that control the sampling behavior.
#
# Sampler(ctx; kwargs...): Initialise the sampler
#
# Each sampler is also callable with arguments that control it's execution
#
# (s::Sampler)(kwargs...): Perform sampling and return sampling results
#

"""Abstract type for samplers"""
abstract type AbstractSampler end

###############################################################################
# ListSampler
###############################################################################

"""
A Sampler struct to compute the amplitudes for a list of bitstrings.
"""
struct ListSampler <: AbstractSampler
    ctx::AbstractContext
    list::Vector{String}
end

"""
    ListSampler(ctx
                ;bitstrings::Vector{String}=String[],
                rank::Integer=0,
                comm_size::Integer=1,
                kwargs...)

Constructor for a ListSampler to produce a portion of the given `bitstrings` determined by
the given `rank` and `comm_size`.
"""
function ListSampler(ctx
                     ;bitstrings::Vector{String}=String[],
                     kwargs...)
    if haskey(kwargs, :num_samples)
        n = kwargs[:num_samples]
        n = min(n, length(bitstrings))
    else
        n = length(bitstrings)
    end

    ListSampler(ctx, bitstrings[1:n])
end

"""
    (s::ListSampler)(max_amplitudes=nothing, kwargs...)

Callable for ListSampler struct. Calculates amplitudes for each bitstring in the list
"""
function (s::ListSampler)(;max_amplitudes=nothing, kwargs...)
    bs = if max_amplitudes === nothing
        s.list
    else s.list[1:min(max_amplitudes, length(s.list))] end

    amps = ctxmap(x -> compute_amplitude!(s.ctx, x; kwargs...), s.ctx, bs)
    amps = ctxgather(s.ctx, amps)
    if amps !== nothing return (bs, amps) end
end

create_sampler(ctx, sampler_params) = get_constructor(sampler_params[:method])(ctx; sampler_params[:params]...)
get_constructor(func_name::String) = getfield(@__MODULE__, Symbol(func_name*"Sampler"))

end