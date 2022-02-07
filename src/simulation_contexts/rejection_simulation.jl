#===================================================#
# Rejection Sampling Simulation
#===================================================#
struct RejectionSim <: AbstractSimContext end

# mutable struct UniformSim <: AbstractSimContext
#     num_qubits::Integer
#     num_amps::Integer
#     seed::Integer
#     rng::MersenneTwister
#     rng_checkpoint::MersenneTwister
#     next_bitstring::Integer

#     slices::CartesianIndices
#     contraction_jobs::Vector{CartesianIndex}
# end

# function get_bitstring!(ctx::RejectionSim, i::Integer)
#     if i < ctx.next_bitstring
#         ctx.rng_checkpoint = MersenneTwister(ctx.seed)
#         ctx.next_bitstring = 1
#     end
#     copy!(ctx.rng, ctx.rng_checkpoint)
#     if i > ctx.next_bitstring
#         [rand(ctx.rng, Bool, ctx.num_qubits) for _ in ctx.next_bitstring:i-1]
#         ctx.rng_checkpoint = copy(ctx.rng)
#         ctx.next_bitstring = i
#     end
#     rand(ctx.rng, Bool, ctx.num_qubits)
# end