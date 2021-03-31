using QXRunner
using Test
using TestSetExtensions
using Logging

@testset "QXRunner.jl" begin
    @includetests ARGS
end
