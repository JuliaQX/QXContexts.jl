module TestContexts

using Test

using QXContexts

include("utils.jl")

@testset "Test contexts module" begin

    @testset "Test SliceIterator" begin
        dims = [2,3,4]
        si = SliceIterator(dims)
        @test length(si) == prod(dims)
        @test si[1] == [1,1,1]
        @test si[dims...] == [2,3,4]

        si = SliceIterator(dims, 1, 10)
        @test length(si) == 10
    end

    @testset "Test QXContext" begin
        cg = ComputeGraph(build_tree(sample_cmds), deepcopy(sample_tensors))
        ctx = QXContext(cg)

        # contract without setting view parameters
        set_open_bonds!(ctx, "0")
        output_0 = ctx()
        @test size(output_0) == (2,)

        set_open_bonds!(ctx, "1")
        output_1 = ctx()
        @test size(output_1) == (2,)

        # contract while summing over view parameters
        @test compute_amplitude!(ctx, "0") ≈ output_0
        @test compute_amplitude!(ctx, "1") ≈ output_1

        @test compute_amplitude!(ctx, "1", max_slices=0) ≈ output_1
    end
end

end