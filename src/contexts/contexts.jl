module Contexts

# some cuda related utilities
include("cuda.jl")
# data structures for iterating over slices
include("slices.jl")
# context interface and QXContext implementation
include("base.jl")
# MPI context implementation
include("mpi_context.jl")
# Context using Distributed.jl implementation
# include("dist_context.jl")

end