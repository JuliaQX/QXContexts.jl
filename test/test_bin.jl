module TestCLI
using Test
using FileIO

# include source of bin file here to avoid world age issues
include("../bin/qxrun.jl")

@testset "Test prepare rqc input cli script" begin
    ghz_results = Dict{String, ComplexF32}(
            "11111" => 1/sqrt(2) + 0im,
            "11010" => 0 + 0im,
            "01110" => 0 + 0im,
            "00110" => 0 + 0im,
            "10100" => 0 + 0im,
            "01001" => 0 + 0im
        )
    ghz_example_dir = joinpath(dirname(@__DIR__), "examples", "ghz")
    dsl_input = joinpath(ghz_example_dir, "ghz_5.qx")
    # create empty temporary directory
    mktempdir() do path
        output_fname = joinpath(path, "out.jld2")
        args = ["-d", dsl_input,
                "-o", output_fname]
        main(args)
        @test isfile(output_fname)
        output = load(output_fname, "results")
        @test all([output[x] ≈ ghz_results[x] for x in keys(output)])
    end

    mktempdir() do path
        output_fname = joinpath(path, "out.jld2")
        args = ["-d", dsl_input,
                "-o", output_fname,
                "--number-amplitudes", "1"]
        main(args)
        @test isfile(output_fname)
        output = load(output_fname, "results")
        @test all([output[x] ≈ ghz_results[x] for x in ["11111"]])
    end

    mktempdir() do path
        output_fname = joinpath(path, "out.jld2")
        args = ["-d", dsl_input,
                "-o", output_fname,
                "--number-amplitudes", "2",
                "--number-slices", "1"]
        main(args)
        @test isfile(output_fname)
        output = load(output_fname, "results")
        @test all([output[x] ≈ ghz_results[x] for x in ["11111", "11010"]])
    end

end
end