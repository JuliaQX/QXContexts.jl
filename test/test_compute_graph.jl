module ComputeGraphTests

using Test

using QXContexts

include("utils.jl")

@testset "Compute Graph Tests" begin

    @testset "Test commands" begin
        read_io = c -> begin
            io = IOBuffer()
            write(io, c)
            String(take!(io))
        end

        contract_example = "ncon t3 1,2,4 t1 1,2,3 t2 3,4"
        c = ContractCommand(contract_example)
        @test strip(read_io(c)) == contract_example # strip to remove \n
        @test inputs(c) == [:t1, :t2]
        @test output(c) == :t3
        @test length(params(c)) == 0

        load_example = "load t1 data_1 2,2"
        c = LoadCommand(load_example)
        @test strip(read_io(c)) == load_example # strip to remove \n
        @test inputs(c) == []
        @test output(c) == :t1
        @test length(params(c)) == 0

        save_example = "save result t3"
        c = SaveCommand(save_example)
        @test strip(read_io(c)) == save_example # strip to remove \n
        @test inputs(c) == [:t3]
        @test output(c) == :result
        @test length(params(c)) == 0

        reshape_example = "reshape t2 t1 1;2,3"
        c = ReshapeCommand(reshape_example)
        @test strip(read_io(c)) == reshape_example # strip to remove \n
        @test inputs(c) == [:t1]
        @test output(c) == :t2
        @test length(params(c)) == 0

        view_example = "view t1_s t1 v1 1 2"
        c = ViewCommand(view_example)
        @test strip(read_io(c)) == view_example # strip to remove \n
        @test inputs(c) == [:t1]
        @test output(c) == :t1_s
        @test length(params(c)) == 1
        @test params(c)[:v1] == 2

        output_example = "output t1 2 2"
        c = OutputCommand(output_example)
        @test strip(read_io(c)) == output_example # strip to remove \n
        @test inputs(c) == []
        @test output(c) == :t1
        @test length(params(c)) == 1
        @test params(c)[:o2] == 2
    end

    @testset "Test build tree" begin
        tree = build_tree(sample_cmds)
        @test length(tree) == length(sample_cmds)
        @test output(tree) == :result

        # test get commands function
        @test length(get_commands(tree, LoadCommand)) == 2
        @test length(get_commands(tree, Union{LoadCommand, ReshapeCommand})) == 3

        # test params
        @test Set(collect(keys(params(tree)))) == Set([:o1, :v1])

        # create compute graph
        cg = ComputeGraph(tree, deepcopy(sample_tensors))
        @test output(cg) == :result
    end

    @testset "Test dsl" begin
        mktempdir() do path
            tree = build_tree(sample_cmds)
            fn = joinpath(path, "foo.qx")
            open(fn, "w") do io
                write(io, tree)
            end

            tree2, metadata = parse_dsl(fn)
            @test length(tree) == length(tree2)

            fn2 = joinpath(path, "foo2.qx")
            open(fn2, "w") do io
                write(io, tree2)
            end

            dsl_1 = open(fn, "r") do io read(io, String) end
            dsl_2 = open(fn2, "r") do io read(io, String) end

            @test dsl_1 == dsl_2
        end
    end
end

end