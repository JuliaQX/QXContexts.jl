using QXRunner
using MPI
using Logging
using Random

import QXRunner.Logger: @perf

MPI.Init()
comm = MPI.COMM_WORLD
rank = MPI.Comm_rank(comm)

#io = nothing
if MPI.Comm_size(comm) > 1
    io = MPI.File.open(comm, "mpi_io.dat", read=true,  write=true, create=true)
else
    io = stdout
end
global_logger(QXRunner.Logger.QXLogger(io, Logging.Error, Dict{Any, Int64}(), false))

@info "Hello world, I am $(rank) of $(MPI.Comm_size(comm)) world-size"
@warn "Rank $(rank) doesn't like what you are doing"
@error "Rank $(rank) is very unhappy!"

if rank == 2
    @info "Hello again from rank $(rank)"
    a = @perf sum(rand(100,100) * rand(100,100))
    println(a)
else
    @warn "I AM RANK $(rank)"
end