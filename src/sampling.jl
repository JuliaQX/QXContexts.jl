module Sampling

export ListSampler, RejectionSampler, Samples
export construct_sampler, accept!

using Random
using DataStructures
import Base.iterate


abstract type AbstractSampler end


"""
Struct to hold the results of contraction and output sampling.
"""
struct Samples{T}
    bitstrings::DefaultDict{String, Int}
    amplitudes::Dict{String, T}
end

Samples() = Samples(DefaultDict{String, Int}(0), Dict{String, ComplexF64}())


###############################################################################
# ListSampler
###############################################################################

"""
A Sampler struct to compute the amplitudes of a list of bitstrings.
"""
struct ListSampler <: AbstractSampler
    list::Vector{String}
    ListSampler(params) = new(params["bitstrings"])
end


iterate(sampler::ListSampler) = (sampler.list, nothing)
iterate(sampler::ListSampler, ::Nothing) = nothing


function accept!(results::Samples, ::ListSampler, bitstring_batch::Vector{String})
    for bitstring in bitstring_batch
        results.bitstrings[bitstring] += 1
    end
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


function iterate(sampler::RejectionSampler)
    num_amps = sampler.num_samples - sampler.accepted
    if num_amps > 0
        return [prod(rand(sampler.rng, ["0", "1"], sampler.num_qubits)) for _ in 1:(num_amps)], nothing
    else
        return nothing
    end
end

iterate(sampler::RejectionSampler, ::Nothing) = iterate(sampler)


function accept!(results::Samples, sampler::RejectionSampler, bitstring_batch::Vector{String})
    for bitstring in bitstring_batch
        amp = results.amplitudes[bitstring]
        Np = 2^sampler.num_qubits * abs(amp)^2
        sampler.fix_M && (sampler.M = max(Np, sampler.M))

        u = rand(sampler.rng)
        if u < Np / sampler.M
            sampler.accepted += 1
            results.bitstrings[bitstring] += 1
        end
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
    batch_size::Int64
    total_batches::Int64
    rng::MersenneTwister
end

function UniformSampler(params)
    num_qubits = params["num_qubits"]
    num_samples = params["num_samples"]
    batch_size = params["batch_size"]
    total_batches = params["total_batches"]
    rng = MersenneTwister(params["seed"])
    UniformSampler(num_qubits, num_samples, batch_size, total_batches, rng)
end


function iterate(sampler::UniformSampler)
    if sampler.total_batches * sampler.batch_size < sampler.num_samples
        sampler.total_batches += 1
        return [prod(rand(sampler.rng, ["0", "1"], sampler.num_qubits)) for _ in 1:(sampler.batch_size)], nothing
    else
        return nothing
    end
end

iterate(sampler::UniformSampler, ::Nothing) = iterate(sampler)


function accept!(results::Samples, ::UniformSampler, bitstring_batch::Vector{String})
    for bitstring in bitstring_batch
        results.bitstrings[bitstring] += 1
    end
end

###############################################################################
# Sampler Constructor
###############################################################################


CONSTRUCTORS = Base.ImmutableDict(
    "rejection" => RejectionSampler,
    "list" => ListSampler
)

function construct_sampler(params)
    CONSTRUCTORS[params["output_method"]](params)
end

end