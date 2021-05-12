module Sampling

export ListSampler, RejectionSampler, UniformSampler
export create_sampler, accept!

import MPI

using Random
using DataStructures
using QXContexts.Execution

"""Abstract type for samplers"""
abstract type AbstractSampler end

###############################################################################
# ListSampler
###############################################################################

"""
A Sampler struct to compute the amplitudes for a list of bitstrings.
"""
struct ListSampler <: AbstractSampler
    list::Vector{String}
end

"""
    ListSampler(;bitstrings::Vector{String}=String[], 
                rank::Integer=0, 
                comm_size::Integer=1, 
                kwargs...)

Constructor for a ListSampler to produce a portion of the given `bitstrings` determined by 
the given `rank` and `comm_size`.
"""
function ListSampler(;bitstrings::Vector{String}=String[], 
                    rank::Integer=0,
                    comm_size::Integer=1, 
                    kwargs...)
    range = get_rank_range(length(bitstrings), comm_size, rank)
    bitstrings = bitstrings[range]
    if haskey(kwargs, :num_samples)
        num_amplitudes = kwargs[:num_samples]
        num_amplitudes = get_rank_size(num_amplitudes, comm_size, rank)
        num_amplitudes = min(num_amplitudes, length(bitstrings))
    else
        num_amplitudes = length(bitstrings)
    end
    ListSampler(bitstrings[1:num_amplitudes])
end

"""Iterator interface functions for ListSampler"""
Base.iterate(sampler::ListSampler) = Base.iterate(sampler.list)
Base.iterate(sampler::ListSampler, state) = Base.iterate(sampler.list, state)

"""
    accept!(results::Samples{T}, ::ListSampler, bitstring::String) where T<:Complex

Does nothing as a ListSampler is not for collecting samples.
"""
function accept!(::Samples{T}, ::ListSampler, ::String) where T<:Complex
    nothing
end

###############################################################################
# RejectionSampler
###############################################################################

"""
A Sampler struct to use rejection sampling to produce output.
"""
mutable struct RejectionSampler <: AbstractSampler
    num_qubits::Integer
    num_samples::Integer
    accepted::Integer
    M::Real
    fix_M::Bool
    rng::MersenneTwister
end

"""
    function RejectionSampler(;num_qubits::Integer, 
                              num_samples::Integer, 
                              M::Real=0.0001, 
                              fix_M::Bool=false, 
                              seed::Integer=42,
                              rank::Integer=0,
                              comm_size::Integer=1,
                              kwargs...)

Constructor for a RejectionSampler to produce and accept a number of bitstrings.
"""
function RejectionSampler(;num_qubits::Integer, 
                          num_samples::Integer, 
                          M::Real=0.0001, 
                          fix_M::Bool=false, 
                          seed::Integer=42,
                          rank::Integer=0,
                          comm_size::Integer=1,
                          kwargs...)
    # Evenly divide the number of bitstrings to be sampled amongst the subgroups of ranks.
    num_amplitudes = get_rank_size(num_samples, comm_size, rank)
    rng = MersenneTwister(seed + rank)
    RejectionSampler(num_qubits, num_samples, 0, M, fix_M, rng)
end

"""Iterator interface functions for RejectionSampler"""
Base.iterate(sampler::RejectionSampler, ::Nothing) = iterate(sampler)

function Base.iterate(sampler::RejectionSampler)
    if sampler.accepted >= sampler.num_samples
        return nothing
    else
        return prod(rand(sampler.rng, ["0", "1"], sampler.num_qubits)), nothing
    end
end

"""
    accept!(results::Samples{T}, sampler::RejectionSampler, bitstring::String) where T<:Complex

Accept or reject the given bitstring as a sample using the rejection method and update 
`results` accordingly.
"""
function accept!(results::Samples{T}, sampler::RejectionSampler, bitstring::String) where T<:Complex
    # Get the amplitude for the given bitstring and the parameters for the rejection method.
    amp = results.amplitudes[bitstring]
    Np = 2^sampler.num_qubits * abs(amp)^2
    sampler.fix_M && (sampler.M = max(Np, sampler.M))

    # Accept the given bitstring as a sample with probability Np/M.
    u = rand(sampler.rng)
    if u < Np / sampler.M
        sampler.accepted += 1
        results.bitstrings_counts[bitstring] += 1
    end
end

###############################################################################
# UniformSampler
###############################################################################

"""
A Sampler struct to uniformly sample bitstrings and compute their amplitudes.
"""
mutable struct UniformSampler <: AbstractSampler
    num_qubits::Integer
    num_samples::Integer
    rng::MersenneTwister
end

"""
    UniformSampler(;num_qubits::Integer,
                    num_samples::Integer,
                    seed::Integer=42,
                    rank::Integer=0,
                    comm_size::Integer=1,
                    kwargs...)

Constructor for a UniformSampler to uniformly sample bitstrings.
"""
function UniformSampler(;num_qubits::Integer,
                        num_samples::Integer,
                        seed::Integer=42,
                        rank::Integer=0,
                        comm_size::Integer=1,
                        kwargs...)
    # Evenly divide the number of bitstrings to be sampled amongst the subgroups of ranks.
    num_samples = (num_samples ÷ comm_size) + (rank < num_samples % comm_size)
    rng = MersenneTwister(seed + rank)
    UniformSampler(num_qubits, num_samples, rng)
end

"""Iterator interface functions for UniformSampler"""
Base.iterate(sampler::UniformSampler) = iterate(sampler, 0)

function Base.iterate(sampler::UniformSampler, samples_produced::Integer)
    if samples_produced < sampler.num_samples
        new_bitstring = prod(rand(sampler.rng, ["0", "1"], sampler.num_qubits))
        return new_bitstring, samples_produced + 1
    else
        return nothing
    end
end

"""
    accept!(results::Samples{T}, ::UniformSampler, bitstring::String) where T<:Complex

Accept the given bitstring as a sample and update `results` accordingly.
"""
function accept!(results::Samples{T}, ::UniformSampler, bitstring::String) where T<:Complex
    results.bitstrings_counts[bitstring] += 1
end

###############################################################################
# Sampler Constructor
###############################################################################

"""
    create_sampler(params)

Returns a sampler whose type and parameters are specified in the Dict `params`.

Additional parameters that determine load balancing and totale amout of work to be done
are set by `max_amplitudes` and the Context `ctx`.
"""
function create_sampler(params, ctx, max_amplitudes=nothing)
    max_amplitudes === nothing || (params[:params][:num_samples] = max_amplitudes)
    create_sampler(params, ctx)
end

function create_sampler(params, ctx::QXMPIContext)
    params[:rank] = MPI.Comm_rank(ctx.comm) ÷ MPI.Comm_size(ctx.sub_comm)
    params[:comm_size] = MPI.Comm_size(ctx.comm) ÷ MPI.Comm_size(ctx.sub_comm)
    create_sampler(params)
end

create_sampler(params, ctx::QXContext{T}) where T = create_sampler(params)
create_sampler(params) = get_constructor(params[:method])(;params[:params]...)

get_constructor(func_name::String) = getfield(Main, Symbol(func_name*"Sampler"))

end