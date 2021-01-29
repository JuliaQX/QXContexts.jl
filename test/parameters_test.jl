module ParametersTests

using QXRun
using Test


@testset "Parameter Tests" begin

    @testset "Parameters isequal overload" begin
        ex1 = Parameters(["0000", "0001", "1111"], Symbol.(["\$v1","\$v2"]), CartesianIndices((3,2)))
        ex2 = Parameters(["0000", "0001", "1111"], Symbol.(["\$v2","\$v1"]), CartesianIndices((3,2)))
        ex3 = Parameters(["0000", "0001", "1111"], Symbol.(["\$v1","\$v2"]), CartesianIndices((2,3)))
        ex4 = Parameters(["0000", "0001", "1111"], Symbol.(["\$v2","\$v1"]), CartesianIndices((2,3)))
        ex5 = Parameters(["0001", "0000", "1111"], Symbol.(["\$v1","\$v2"]), CartesianIndices((3,2)))
        ex6 = Parameters(["0011", "0000", "1111"], Symbol.(["\$v1","\$v2"]), CartesianIndices((3,2)))

        @test isequal(ex1, ex1)
        @test !isequal(ex1, ex2)
        @test !isequal(ex1, ex3)
        @test isequal(ex1, ex4)
        @test isequal(ex1, ex5)
        @test !isequal(ex1, ex6)

        @test isequal(ex2, ex2)
        @test isequal(ex2, ex3)
        @test !isequal(ex2, ex4)
        @test !isequal(ex2, ex5)
        @test !isequal(ex2, ex6)
    end

    @testset "SubstitutionSet isequal overload" begin
        # Baseline dict
        d1 = Dict(
            Symbol("\$o1") => "output_0",
            Symbol("\$o2") => "output_0",
            Symbol("\$o3") => "output_0",
            Symbol("\$o4") => "output_1"
        )
        # Same as baseline with changed order
        d2 = Dict(
            Symbol("\$o1") => "output_0",
            Symbol("\$o3") => "output_0",
            Symbol("\$o4") => "output_1",
            Symbol("\$o2") => "output_0"
        )
        # Differs from d1 and d2
        d3 = Dict(
            Symbol("\$o1") => "output_0",
            Symbol("\$o2") => "output_0",
            Symbol("\$o3") => "output_1",
            Symbol("\$o4") => "output_1"
        )

        ex1 = SubstitutionSet(d1, Symbol.(["\$v1","\$v2"]), CartesianIndices((3,2)))
        ex2 = SubstitutionSet(d1, Symbol.(["\$v2","\$v1"]), CartesianIndices((3,2)))
        ex3 = SubstitutionSet(d1, Symbol.(["\$v1","\$v2"]), CartesianIndices((2,3)))
        ex4 = SubstitutionSet(d1, Symbol.(["\$v2","\$v1"]), CartesianIndices((2,3)))
        @test isequal(ex1, ex1)
        @test !isequal(ex1, ex2)
        @test !isequal(ex1, ex3)
        @test isequal(ex1, ex4)
        # Change subs dict - the sets will still be equal
        ex5 = SubstitutionSet(d2, Symbol.(["\$v2","\$v1"]), CartesianIndices((3,2)))
        ex6 = SubstitutionSet(d2, Symbol.(["\$v1","\$v2"]), CartesianIndices((2,3)))
        ex7 = SubstitutionSet(d2, Symbol.(["\$v2","\$v1"]), CartesianIndices((2,3)))
        @test !isequal(ex1, ex5)
        @test !isequal(ex1, ex6)
        @test isequal(ex1, ex7)
        # Change subs dict - the sets will NOT be equal
        ex8 = SubstitutionSet(d3, Symbol.(["\$v2","\$v1"]), CartesianIndices((3,2)))
        ex9 = SubstitutionSet(d3, Symbol.(["\$v1","\$v2"]), CartesianIndices((2,3)))
        ex10 = SubstitutionSet(d3, Symbol.(["\$v2","\$v1"]), CartesianIndices((2,3)))
        @test !isequal(ex1, ex8)
        @test !isequal(ex1, ex9)
        @test !isequal(ex1, ex10)
    end


    parameter_file_contents = """
partitions:
    parameters:
      v1: 2
      v2: 2
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