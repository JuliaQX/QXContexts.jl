module Sampling

export ListSampler, RejectionSampler, Samples
export construct_sampler, accept!

using Random
using DataStructures

"""
Struct to hold the results of a simulation.
"""
struct Samples{T}
    bitstrings::DefaultDict{String, Int}
    amplitudes::Dict{String, T}
end

Samples() = Samples(DefaultDict{String, Int}(0), Dict{String, ComplexF32}())

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
    num_amplitudes::Int64
end

function ListSampler(params)
    if haskey(params, "num_samples")
        num_amplitudes = params["num_samples"]
        num_amplitudes = min(num_amplitudes, length(params["bitstrings"]))
    else
        num_amplitudes = length(params["bitstrings"])
    end
    ListSampler(params["bitstrings"], num_amplitudes)
end

"""Iterator interface functions for ListSampler"""
Base.iterate(sampler::ListSampler) = (first(sampler.list), 1)

function Base.iterate(sampler::ListSampler, ind::Integer)
    ind < sampler.num_amplitudes || (return nothing) 
    (sampler.list[ind+1], ind+1)
end

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
    num_qubits::Int64
    num_samples::Int64
    accepted::Int64
    M::Float64
    fix_M::Bool
    rng::MersenneTwister
end

function RejectionSampler(params)
    num_qubits = params["num_qubits"]
    num_samples = params["num_samples"]
    M = params["M"]
    fix_M = params["fix_M"]
    rng = MersenneTwister(params["seed"])
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
        results.bitstrings[bitstring] += 1
    end
end

###############################################################################
# UniformSampler
###############################################################################

"""
A Sampler struct to uniformly sample bitstrings and compute their amplitudes.
"""
mutable struct UniformSampler <: AbstractSampler
    num_qubits::Int64
    num_samples::Int64
    rng::MersenneTwister
end

function UniformSampler(params)
    num_qubits = params["num_qubits"]
    num_samples = params["num_samples"]
    rng = MersenneTwister(params["seed"])
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
    results.bitstrings[bitstring] += 1
end

###############################################################################
# Sampler Constructor
###############################################################################

CONSTRUCTORS = Base.ImmutableDict(
    "rejection" => RejectionSampler,
    "uniform" => UniformSampler,
    "list" => ListSampler
)

"""
    construct_sampler(params)

Returns a sampler whose type is specified in `params`.
"""
function construct_sampler(params)
    CONSTRUCTORS[params["output_method"]](params)
end

end