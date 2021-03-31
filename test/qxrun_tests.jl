module QXRunnerTests

using QXRunner
using JLD2
using FileIO
using Test

@testset "5 qubit GHZ" begin
    Core.eval(Main, :(import JLD2))

    test_path = @__DIR__
    dsl_file         = test_path * "/../examples/ghz/ghz_5.qx"
    param_file       = test_path * "/../examples/ghz/ghz_5.yml"
    input_data_file  = test_path * "/../examples/ghz/ghz_5.jld2"
    output_data_file = tempname() * ".jld2"

    expected = Dict{String, ComplexF32}(
        "11111" => 1/sqrt(2) + 0im,
        "11010" => 0 + 0im,
        "01110" => 0 + 0im,
        "00110" => 0 + 0im,
        "10100" => 0 + 0im,
        "01001" => 0 + 0im
    )

    try
        execute(dsl_file, param_file, input_data_file, output_data_file)
        # ensure all dictionary entries match
        output = FileIO.load(output_data_file, "results")
        @test all([output[x] ≈ expected[x] for x in keys(output)])
    finally
        rm(output_data_file, force=true)
    end
end

end
