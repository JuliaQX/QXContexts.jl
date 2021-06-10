module ComputeGraphs

# command definitions
include("cmds.jl")
# compute graph data structure
include("tree.jl")
# tree optimisation functions
include("tree_opt.jl")
# tree statistics
include("tree_stats.jl")
# functions to parse dsl file
include("dsl.jl")

end
