module ExecutionTests

using QXRun.DSL
using QXRun.Param
using QXRun.Execution
using Test

import JLD

function generate_command_list()
    return CommandList([
        LoadCommand(:o1_0, :output_0)
        LoadCommand(:o1_1, :output_1)
        LoadCommand(:o2_0, :output_0)
        LoadCommand(:o2_1, :output_1)
        LoadCommand(:o3_0, :output_0)
        LoadCommand(:o3_1, :output_1)
        LoadCommand(:t872, :data_1)
        LoadCommand(:t873, :data_2)
        LoadCommand(:t874, :data_2)
        LoadCommand(:t875, :data_3)
        LoadCommand(:t876, :data_3)
        LoadCommand(:t877, :data_3)
        ParametricCommand{ViewCommand}("t872_v1 t872 1 \$v1")
        ParametricCommand{ViewCommand}("t873_v1 t873 4 \$v1")
        ParametricCommand{ViewCommand}("t873_v1_v2 t873_v1 1 \$v2")
        ParametricCommand{ViewCommand}("t874_v2 t874 4 \$v2")
        ParametricCommand{ViewCommand}("t874_v2_v3 t874_v2 1 \$v3")
        ParametricCommand{ViewCommand}("t880_v3 \$o3 1 \$v3")
        ParametricCommand{ViewCommand}("t874_v2_v3_v4 t874_v2_v3 2 \$v4")
        ParametricCommand{ViewCommand}("t879_v4 \$o2 1 \$v4")
        ParametricCommand{NconCommand}("t881 t873_v1_v2 -1,1,-2,-3 \$o1 1")
        DeleteCommand(:t873_v1_v2)
        ParametricCommand{DeleteCommand}("\$o1")
        NconCommand(:t882, :t881, [-1,1,-2], :t876, [1])
        DeleteCommand(:t881)
        DeleteCommand(:t876)
        NconCommand(:t883, :t872_v1, [-1,1], :t875, [1])
        DeleteCommand(:t872_v1)
        DeleteCommand(:t875)
        NconCommand(:t884, :t874_v2_v3_v4, [-1,-2,1,-3], :t877, [1])
        DeleteCommand(:t874_v2_v3_v4)
        DeleteCommand(:t877)
        NconCommand(:t885, :t880_v3, [1], :t879_v4, [-1])
        DeleteCommand(:t880_v3)
        DeleteCommand(:t879_v4)
        NconCommand(:t886, :t885, [1,-1], :t882, [-2,-3])
        DeleteCommand(:t885)
        DeleteCommand(:t882)
        NconCommand(:t887, :t886, [-1,-2,-3,1], :t883, [1])
        DeleteCommand(:t886)
        DeleteCommand(:t883)
        NconCommand(:t888, :t887, [1,2,3], :t884, [1,2,3])
        DeleteCommand(:t887)
        DeleteCommand(:t884)
        SaveCommand(:t888, :output)
    ])
end

function generate_parameters()
    return Parameters(
        ["000", "001", "111"],
        Symbol.(["\$v1", "\$v2", "\$v3", "\$v4"]),
        CartesianIndices((2,2,2,2))
    )
end

function generate_input_data_file(fname::String, data::Dict{String, T}) where T
    JLD.jldopen(fname, "w") do file
        for (label, tensor) in data
            file[label] = tensor
        end
    end
end

@testset "Execution Tests" begin

    @testset "Local Reduction" begin
        d = Dict(
            :a => [1,1,1],
            :b => [2,2,2],
            :c => [3,3,3],
        )
        @test reduce_nodes(d) == 18

        push!(d[:b], 2)
        @test_throws DimensionMismatch reduce_nodes(d) == 18

        push!(d[:a], 1)
        push!(d[:c], 3)
        @test reduce_nodes(d) == 24
    end

    test_data = Dict{String, Array{ComplexF32}}(
        "data_1" => convert(Array{ComplexF32}, [1 1; 1 -1] / sqrt(2)),
        "data_2" => convert(Array{ComplexF32}, reshape([1 0 0 0; 0 1 0 1; 0 0 0 1; 0 0 1 0], 2, 2, 2, 2)),
        "data_3" => convert(Array{ComplexF32}, [1; 0]),
        "output_0" => convert(Array{ComplexF32}, [1; 0]),
        "output_1" => convert(Array{ComplexF32}, [0; 1]),
        "node_1" => convert(Array{ComplexF32}, [1 2; 3 4]),
        "node_2" => convert(Array{ComplexF32}, [1 2; 3 4]),
        "test_result" => convert(Array{ComplexF32}, [1 2; 3 4])
    )

    input_data_filename = tempname()
    output_data_filename = tempname()
    try
        generate_input_data_file(input_data_filename, test_data)

        @testset "Execution Context" begin
            cmds = generate_command_list()
            params = generate_parameters()

            ctx = QXContext(cmds, params, input_data_filename, output_data_filename)
            
            # Check default data type
            @test typeof(ctx.data) <: Dict{Symbol, Array{ComplexF32}}

            expected = Dict{String, ComplexF32}(
                "000" => 1 / sqrt(2),
                "001" => 0,
                "111" => 1 / sqrt(2)
            )

            result = execute!(deepcopy(ctx))
            @test result == expected

            @testset "Execute LoadCommand" begin
                local_ctx = deepcopy(ctx)
                command = LoadCommand(:node_1, :node_1)
                execute!(command, local_ctx)

                @test local_ctx.data[:node_1] == test_data["node_1"] 
            end

            @testset "Execute SaveCommand" begin
                local_ctx = deepcopy(ctx)
                local_ctx.data[:test] = test_data["test_result"]
                command = SaveCommand(:test, :test_label)
                execute!(command, local_ctx)

                @test JLD.load(local_ctx.output_file, "test_label") == test_data["test_result"] 
            end

            @testset "Execute DeleteCommand" begin
                local_ctx = deepcopy(ctx)
                local_ctx.data[:test] = test_data["test_result"]
                command = DeleteCommand(:test)
                execute!(command, local_ctx)

                @test length(local_ctx.data) == 0
            end

            @testset "Execute ReshapeCommand" begin
                local_ctx = deepcopy(ctx)
                local_ctx.data[:test] = test_data["test_result"]
                command = ReshapeCommand(:test, [[1,2]])
                execute!(command, local_ctx)

                @test local_ctx.data[:test] == reshape(test_data["test_result"], 4)
            end

            @testset "Execute PermuteCommand" begin
                local_ctx = deepcopy(ctx)
                local_ctx.data[:test] = test_data["test_result"]
                command = PermuteCommand(:test, [2,1])
                execute!(command, local_ctx)

                @test local_ctx.data[:test] == permutedims(test_data["test_result"], [2,1])
            end

            @testset "Execute NconCommand" begin
                local_ctx = deepcopy(ctx)
                local_ctx.data[:input_1] = test_data["node_1"]
                local_ctx.data[:input_2] = test_data["node_2"]
                command = NconCommand(:result, :input_1, [-1,1], :input_2, [1,-2])
                execute!(command, local_ctx)

                @test local_ctx.data[:result] == test_data["node_1"] * test_data["node_2"];
            end

            @testset "Execute ViewCommand" begin
                local_ctx = deepcopy(ctx)
                local_ctx.data[:test] = test_data["test_result"]
                command = ViewCommand(:view, :test, 2, [1])
                execute!(command, local_ctx)

                @test all(local_ctx.data[:view] .== @view test_data["test_result"][:,1])
            end

        end
        
    finally
        rm(input_data_filename, force=true)
        rm(output_data_filename, force=true)
    end

end

end