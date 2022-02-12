# include source of bin file here to avoid world age issues
include("../bin/qxsimulate.jl")

@testset "Test cli script" begin
    ghz_example_dir = joinpath(dirname(@__DIR__), "examples", "ghz")
    dsl_input = joinpath(ghz_example_dir, "ghz_5.qx")
    param_file = joinpath(ghz_example_dir, "ghz_5_uniform.yml")

    # Test uniform simaultion
    mktempdir() do path
        output_fname = joinpath(path, "out.txt")
        args = ["-d", dsl_input,
                "-p", param_file,
                "-o", output_fname,
                "-l", path]
        main(args)
        @test isfile(output_fname)
    end

    # Test rejection simaultion
    param_file = joinpath(ghz_example_dir, "ghz_5_rejection.yml")
    mktempdir() do path
        output_fname = joinpath(path, "out.txt")
        args = ["-d", dsl_input,
                "-p", param_file,
                "-o", output_fname,
                "-l", path]
        main(args)
        @test isfile(joinpath(path, "amps_out.txt"))
    end
end