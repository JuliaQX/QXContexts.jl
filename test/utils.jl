# Some useful data structures that are used in multiple tests

using DataStructures

using QXContexts

# expected results for ghz exmaple files included in examples/ghz folder
ghz_results = OrderedDict{String, ComplexF32}(
    "11001" => 0 + 0im,
    "10000" => 0 + 0im,
    "00011" => 0 + 0im,
    "00000" => 1/sqrt(2) + 0im,
    "11000" => 0 + 0im,
    "10010" => 0 + 0im,
    "10111" => 0 + 0im,
    "01010" => 0 + 0im,
    "01101" => 0 + 0im,
    "11111" => 1/sqrt(2) + 0im,
)

# sample set of commands used for testing compute graph
sample_cmds = AbstractCommand[
    LoadCommand(:t1, :data_1, [2,2,2]),
    ReshapeCommand(:t1_r, :t1, [[1],[2,3]]),
    LoadCommand(:t2, :data_2, [4,2]),
    ViewCommand(:t1_s, :t1_r, :v1, 2, 4),
    ViewCommand(:t2_s, :t2, :v1, 1, 4),
    OutputCommand(:t3, 1, 2),
    ContractCommand(:t4, [1,3], :t1_s, [1,2], :t2_s, [2,3]),
    ContractCommand(:t5, [2], :t3, [1], :t4, [1,2]),
    SaveCommand(:result, :t5)
]

# matching tensors for sample commands
sample_tensors = Dict{Symbol, AbstractArray}(
    :data_1 => rand(2,2,2),
    :data_2 => rand(4,2)
)


