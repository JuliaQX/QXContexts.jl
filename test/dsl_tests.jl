module DSLTests

using QXContexts.DSL
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
            "# version: $(DSL.VERSION_DSL)",
            "load node_1 node_1",
            "save node_27 result",
            "reshape node_1 4,1",
            "permute node_1 2,1",
            "ncon node_22 1,2 node_21 3,1,2 node_9 3",
            "view node_13 node_2 4 v1",
        ])
        expected = CommandList([
            LoadCommand(:node_1, :node_1),
            SaveCommand(:node_27, :result),
            ReshapeCommand(:node_1, [[4,1]]),
            PermuteCommand(:node_1, [2,1]),
            NconCommand(:node_22, [1, 2], :node_21, [3,1,2], :node_9, [3]),
            ViewCommand(:node_13, :node_2, 4, :v1)
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
            "# version: $(DSL.VERSION_DSL)",
            "outputs 2",
            "load node_1 data_1",
            "load node_2 data_2",
            "view node_1_s node_1 1 v1",
            "ncon node_3 1,3 node_1_s 1,2 o1 2,3",
        ])

        expected = DSL.CommandList([
            OutputsCommand(2),
            LoadCommand(:node_1, :data_1),
            LoadCommand(:node_2, :data_2),
            ViewCommand(:node_1_s, :node_1, 1, :v1),
            NconCommand(:node_3, [1,3], :node_1_s, [1,2], :o1, [2,3])
        ])

        @testset "Parse DSL buffer" begin
            commands = parse_dsl(command_buffer)

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

                @test all(isequal.(commands, expected))
            finally
                rm(fname, force=true)
            end
        end
    end

    @testset "Test DSL parseing with comments" begin
        command_buffer = Vector{String}([
            "# version: $(DSL.VERSION_DSL)",
            "# metadata metadata",
            "outputs 2",
            "load node_1 data_1",
            "# this next command is very good",
            "load node_2 data_2",
            "view node_1_s node_1 1 v1",
            "ncon node_3 1,3 node_1_s 1,2 o1 2,3",
        ])

        expected = DSL.CommandList([
            OutputsCommand(2),
            LoadCommand(:node_1, :data_1),
            LoadCommand(:node_2, :data_2),
            ViewCommand(:node_1_s, :node_1, 1, :v1),
            NconCommand(:node_3, [1,3], :node_1_s, [1,2], :o1, [2,3])
        ])

        @testset "Parse DSL buffer" begin
            commands = parse_dsl(command_buffer)

            @test all(isequal.(commands, expected))
        end
    end
end

end