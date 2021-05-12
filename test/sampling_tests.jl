module SamplingTests

using QXContexts
using JLD2
using FileIO
using Test
using DataStructures

@testset "Sampling tests" begin

    test_path = dirname(@__DIR__)
    dsl_file = joinpath(test_path, "examples/ghz/ghz_5.qx")
    input_data_file = joinpath(test_path, "examples/ghz/ghz_5.jld2")


    param_file  = joinpath(test_path, "examples/ghz/ghz_5_uniform.yml")

    mktempdir() do path
        output_data_file = joinpath(path, "out.jld2")
        execute(dsl_file, param_file, input_data_file, output_data_file)

        # ensure all dictionary entries match
        output = FileIO.load(output_data_file, "bitstrings_counts")
        @test sum(values(output)) ≈ 10
    end


    param_file = joinpath(test_path, "examples/ghz/ghz_5_rejection.yml")

    mktempdir() do path
        output_data_file = joinpath(path, "out.jld2")
        execute(dsl_file, param_file, input_data_file, output_data_file)

        # ensure all dictionary entries match
        output = FileIO.load(output_data_file, "bitstrings_counts")
        @test length(output) == 2
        @test output["11111"] + output["00000"] == 10
    end
end

end