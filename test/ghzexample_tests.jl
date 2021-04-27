module QXContextsTests

using QXContexts
using JLD2
using FileIO
using Test
using DataStructures

@testset "5 qubit GHZ" begin

    test_path = dirname(@__DIR__)
    dsl_file         = joinpath(test_path, "examples/ghz/ghz_5.qx")
    param_file       = joinpath(test_path, "examples/ghz/ghz_5.yml")
    input_data_file  = joinpath(test_path, "examples/ghz/ghz_5.jld2")

    mktempdir() do path
        output_data_file = joinpath(path, "out.jld2")

        expected = OrderedDict{String, ComplexF32}(
            "01000" => 0 + 0im,
            "01110" => 0 + 0im,
            "10101" => 0 + 0im,
            "10001" => 0 + 0im,
            "10010" => 0 + 0im,
            "11111" => 1/sqrt(2) + 0im,
        )
        expected_vals = collect(values(expected))

        execute(dsl_file, param_file, input_data_file, output_data_file)
        # ensure all dictionary entries match
        output = FileIO.load(output_data_file, "amplitudes")
        output_vals = [output[bitstring] for bitstring in keys(expected)]
        @test output_vals ≈ expected_vals
    end


    param_file = joinpath(test_path, "examples/ghz/ghz_5_rejection.yml")

    mktempdir() do path
        output_data_file = joinpath(path, "out.jld2")
        execute(dsl_file, param_file, input_data_file, output_data_file)

        # ensure all dictionary entries match
        output = FileIO.load(output_data_file, "bitstrings")
        @test length(output) == 2
        @test output["11111"] + output["00000"] == 10
    end
end

end
