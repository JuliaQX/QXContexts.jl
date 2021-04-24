module ExecutionTests

using QXContexts.DSL
using QXContexts.Param
using QXContexts.Execution
using Test

using DataStructures
import JLD2
import FileIO

function generate_command_list()
    return CommandList([
        OutputsCommand(2)
        LoadCommand(:t1, :data_1)
        LoadCommand(:t2, :data_2)
        LoadCommand(:t3, :data_3)
        LoadCommand(:t4, :data_3)
        ViewCommand(:t4_s, :t4, 1, :v1)
        ViewCommand(:t2_s, :t2, 3, :v1)
        ViewCommand(:o1_s, :o1, 1, :v2)
        ViewCommand(:t2_s_s, :t2_s, 2, :v2)
        ViewCommand(:t1_s, :t1, 1, :v2)
        NconCommand(:t7, [1,2], :t4_s, [1], :o1_s, [2])
        NconCommand(:I1, [2,3], :t2_s_s, [1,2,3], :o2, [1])
        NconCommand(:t8, [2], :t7, [1,2], :I1, [2,1])
        NconCommand(:I2, [1], :t1_s, [1,2], :t3, [2])
        NconCommand(:t9, [], :t8, [1], :I2, [1])
        SaveCommand(:t9, :output)
    ])
end

function generate_parameters()
    OrderedDict{Symbol, Int}(:v1 => 2, :v2 => 2)
end

function generate_input_data_file(fname::String, data::Dict{String, T}) where T
    JLD2.jldopen(fname, "w") do file
        for (label, tensor) in data
            file[label] = tensor
        end
    end
end

@testset "Execution Tests" begin

    test_data = Dict{String, Array{ComplexF32}}(
        "data_1" => convert(Array{ComplexF32}, [1 1; 1 -1] / sqrt(2)),
        "data_2" => convert(Array{ComplexF32}, cat([[1 0; 0 1], [0 1; 1 0]]..., dims=3)),
        "data_3" => convert(Array{ComplexF32}, [1, 0])
    )

    input_data_filename = tempname()
    output_data_filename = tempname()
    try
        generate_input_data_file(input_data_filename, test_data)

        @testset "Execution Context" begin
            cmds = generate_command_list()
            params = generate_parameters()

            ctx = QXContext(cmds, params, input_data_filename)

            # Check default data type
            @test typeof(ctx.data) <: Dict{Symbol, Array{ComplexF32}}

            expected = Dict{String, ComplexF32}(
                "00" => 1 / sqrt(2),
                "01" => 0,
                "11" => 1 / sqrt(2)
            )

            ctx_copy = deepcopy(ctx)
            result = Dict(x => compute_amplitude!(ctx_copy, x) for
                          x in keys(expected))
            @test result == expected

            @testset "Execute ReshapeCommand" begin
                local_ctx = deepcopy(ctx)
                a = rand(ComplexF32, 2,2)
                local_ctx.data[:test] = a
                command = ReshapeCommand(:test, [[1,2]])
                execute!(command, local_ctx)

                @test local_ctx.data[:test] == reshape(a, 4)
            end

            @testset "Execute PermuteCommand" begin
                local_ctx = deepcopy(ctx)
                a = rand(ComplexF32, 2,2)
                local_ctx.data[:test] = a
                command = PermuteCommand(:test, [2,1])
                execute!(command, local_ctx)

                @test local_ctx.data[:test] == permutedims(a, [2,1])
            end
        end

    finally
        rm(input_data_filename, force=true)
        rm(output_data_filename, force=true)
    end

end

end