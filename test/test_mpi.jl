# using Random

# @testset "Test MPI specific portions" begin

#     @testset "Test get_rank_size and get_rank_start" begin
#         rng = MersenneTwister(42)
#         ns = rand(1:2000000, 5)
#         ms = rand(1:10, 5)

#         # test that the sum of sizes on each rank sum to total
#         for n in ns
#             for m in ms
#                 @test sum(map(x -> get_rank_size(n, m, x), 0:m-1)) == n
#             end
#         end

#         # test that the start of the next rank is at the start of previous rank plus the size
#         for n in ns
#             for m in ms
#                 test_rank = x -> (get_rank_start(n, m, x-1) + get_rank_size(n, m, x-1) == get_rank_start(n, m, x))
#                 @test all(map(test_rank, 1:m-1))
#             end
#         end
#     end
# end