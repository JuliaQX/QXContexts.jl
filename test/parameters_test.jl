module ParametersTests

using QXRun
using Test

import Base.isequal

for T in (:Parameters, :SubstitutionSet)
    @eval begin
        @generated function isequal(x::$T, y::$T)
            checks = [:(x.$field == y.$field) for field in fieldnames($T)]
            quote all([$(checks...)]) end
        end
    end
end

@testset "Parameter Tests" begin
    parameter_file_contents = """
partitions:
    parameters:
      - v1: 2
      - v2: 2
amplitudes:
  - "0000"
  - "0001"
  - "1111"
"""

    expected_parameters = Parameters(
        ["0000", "0001", "1111"],
        Symbol.(["\$v1", "\$v2"]),
        CartesianIndices((2,2))
    )

    @testset "Generating multi-index partitions" begin
        @test begin
            input = [Dict("v1" => 2), Dict("v2" => 2)]
            expected = (
                ["v1", "v2"],
                CartesianIndices((2,2))
            )
            QXRun.multi_index_partitions(input) == expected
        end

        @test begin
            input = [Dict("v1" => 2), Dict("v2" => 2), Dict("v3" => 4)]
            expected = (
                ["v1", "v2", "v3"],
                CartesianIndices((2,2,4))
            )
            QXRun.multi_index_partitions(input) == expected
        end
    end


    fname = tempname()
    try
        open(fname, "w") do file
            write(file, parameter_file_contents)
        end

        @testset "Parsing Parameter file" begin
            p = Parameters(fname)

            @test length(p) == length(expected_parameters) == 3
            @test size(p) == size(expected_parameters) == (3, 4)
            @test isequal(p, expected_parameters)

            @test all(isequal.(collect(p), [x for x in p]))
        end


        @testset "Generating a SubstitutionSet" begin
            expected_substitution_set = SubstitutionSet(
                Dict(
                    Symbol("\$o1") => "output_0",
                    Symbol("\$o2") => "output_0",
                    Symbol("\$o3") => "output_0",
                    Symbol("\$o4") => "output_1"
                ),
                expected_parameters.symbols,
                expected_parameters.values
            )

            @test_throws BoundsError expected_parameters["2"]
            substitution_set = expected_parameters["0001"]

            @test length(substitution_set) == length(expected_substitution_set) == 4
            @test size(substitution_set) == size(expected_substitution_set) == (4,)
            @test isequal(substitution_set, expected_substitution_set)
            @test isequal(expected_parameters[2], expected_substitution_set)

            @test_throws BoundsError expected_substitution_set[100000]
            substitution = substitution_set[1]

            @test substitution == Dict(
                Symbol("\$v1") => "1",
                Symbol("\$v2") => "1",
                Symbol("\$o1") => "output_0",
                Symbol("\$o2") => "output_0",
                Symbol("\$o3") => "output_0",
                Symbol("\$o4") => "output_1",
            )

            @test all(isequal.(collect(substitution_set), [x for x in substitution_set]))
        end
        
    finally
        rm(fname, force=true)
    end
end

end