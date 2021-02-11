module QXRunTests

using QXRun
using JLD
using Test

@testset "5 qubit GHZ" begin
    Core.eval(Main, :(import JLD))

    test_path = @__DIR__
    dsl_file         = test_path * "/../examples/ghz/ghz_5.tl"
    param_file       = test_path * "/../examples/ghz/ghz_5.yml"
    input_data_file  = test_path * "/../examples/ghz/ghz_5.jld"
    output_data_file = tempname() * ".jld"

    expected = Dict{String, ComplexF32}(
        "00111" => 0 + 0im,
        "10111" => 0 + 0im,
        "11000" => 0 + 0im,
        "00111" => 0 + 0im,
        "00000" => 1/sqrt(2) + 0im,
        "11111" => 1/sqrt(2) + 0im,
    )

    try
        execute(dsl_file, param_file, input_data_file, output_data_file)

        @test expected == JLD.load(output_data_file, "results")
    finally
        rm(output_data_file, force=true)
    end
end

end
