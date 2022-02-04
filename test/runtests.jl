using QXContexts
using Test
using TestSetExtensions
using Logging

# @testset ExtendedTestSet "QXContexts.jl" begin
#     @includetests ARGS
# end

include("test_compute_graph.jl")
include("test_contexts.jl")
include("test_sim_contexts.jl")
# include("test_loggers.jl")
include("test_bin.jl")