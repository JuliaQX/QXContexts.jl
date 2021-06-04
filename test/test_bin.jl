module TestCLI
using Test
using FileIO
using DataStructures

include("utils.jl")

# include source of bin file here to avoid world age issues
include("../bin/qxrun.jl")

@testset "Test prepare rqc input cli script" begin
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
        @test all([x[2] ≈ ghz_results[x[1]] for x in zip(output...)])
    end

    mktempdir() do path
        output_fname = joinpath(path, "out.jld2")
        args = ["-d", dsl_input,
                "-o", output_fname,
                "--number-amplitudes", "1"]
        main(args)
        @test isfile(output_fname)

        output = load(output_fname, "results")
        @test length(output[1]) == 1
        @test output[2][1] ≈ ghz_results["11001"]
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
        @test length(output) == 2
        @test all([output[2][x] ≈ ghz_results[output[1][x]] for x in 1:2])
    end

end
end