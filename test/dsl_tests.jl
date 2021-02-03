module DSLTests

using QXRun
using Test

import Base.isequal

isequal(x::T, y::U) where {T <: AbstractCommand, U <: AbstractCommand} = false

@generated function isequal(x::T, y::T) where T <: AbstractCommand
    checks = [:(x.$field == y.$field) for field in fieldnames(T)]
    quote all([$(checks...)]) end
end

@testset "DSL Tests" begin
    @testset "Standard DSL" begin
        command_buffer = Vector{String}([
            "load node_1 node_1",
            "save node_27 result",
            "del node_8",
            "reshape node_1 4,1",
            "permute node_1 2,1",
            "ncon node_22 node_21 1,-1,-2 node_9 1",
            "view node_13 node_2 4 0",
        ])
        expected = CommandList([
            LoadCommand(:node_1, :node_1),
            SaveCommand(:node_27, :result),
            DeleteCommand(:node_8),
            ReshapeCommand(:node_1, [[4,1]]),
            PermuteCommand(:node_1, [2,1]),
            NconCommand(:node_22, :node_21, [1,-1,-2], :node_9, [1]),
            ViewCommand(:node_13, :node_2, 4, [0])
        ])

        @testset "Parse DSL buffer" begin
            commands = parse_dsl(command_buffer)
            @test all(isequal.(commands, expected))
        end

        @testset "Parse DSL file" begin
            fname = tempname()
            try
                open(fname, "w") do file
                    for line in command_buffer
                        write(file, line, "\n")
                    end
                end

                commands = parse_dsl(fname)

                @test all(isequal.(commands, expected))
            finally
                rm(fname, force=true)
            end
        end
    end

    @testset "Parametric DSL" begin
        command_buffer = Vector{String}([
            "outputs 2",
            "load node_1 node_1",
            "load node_1 \$o1",
            "save \$o4 result",
            "del node_8",
            "reshape node_1 4,\$v1",
            "permute node_1 \$v2,\$v1",
            "ncon node_22 \$o2 1,\$v1,-2 \$o3 \$v2",
            "view node_13 node_2 4 \$v2",
        ])

        subs = QXRun.SubstitutionType(
            Symbol("\$v1") => "1",
            Symbol("\$v2") => "2",
            Symbol("\$o1") => "output_0",
            Symbol("\$o2") => "output_0",
            Symbol("\$o3") => "output_0",
            Symbol("\$o4") => "output_1"
        )

        expected = CommandList([
            LoadCommand(:o1_0, :output_0),
            LoadCommand(:o1_1, :output_1),
            LoadCommand(:o2_0, :output_0),
            LoadCommand(:o2_1, :output_1),
            LoadCommand(:node_1, :node_1),
            LoadCommand(:node_1, :output_0),
            SaveCommand(:output_1, :result),
            DeleteCommand(:node_8),
            ReshapeCommand(:node_1, [[4,1]]),
            PermuteCommand(:node_1, [2,1]),
            NconCommand(:node_22, :output_0, [1,1,-2], :output_0, [2]),
            ViewCommand(:node_13, :node_2, 4, [2])
        ])

        @testset "Parse DSL buffer" begin
            commands = parse_dsl(command_buffer)
            apply_substitution!(commands, subs)

            @test all(isequal.(commands, expected))
            # Test non-ascii input
            @test_throws ArgumentError parse_dsl(["∈"])
        end

        @testset "Parse DSL file" begin
            fname = tempname()
            try
                open(fname, "w") do file
                    for line in command_buffer
                        write(file, line, "\n")
                    end
                end

                commands = parse_dsl(fname)
                apply_substitution!(commands, subs)

                @test all(isequal.(commands, expected))
            finally
                rm(fname, force=true)
            end
        end
    end
end

end