using MPI
using Distributed
using CUDA

#===================================================#
# Get/Set arguments
#===================================================#
dsl_file = "../examples/ghz/ghz_5.qx"
data_file = "../examples/ghz/ghz_5.jld2"
param_file = "../examples/ghz/ghz_5_uniform.yml"

output_file = "results.txt"
elt = ComplexF32



#===================================================#
# Initialise processes
#===================================================#

# Initialise mpi ranks
MPI.Init()
comm = MPI.COMM_WORLD
comm_size = MPI.Comm_size(comm)
rank = MPI.Comm_rank(comm)
root = 0

# Start up local Julia cluster
using_cuda = CUDA.functional() && !isempty(devices())
if using_cuda
    addprocs(length(devices()); exeflags="--project")
    @everywhere workers() using CUDA # TODO: Maybe this can be included in exeflags above

    # Assign GPUs to worker processes
    for (worker, gpu_dev) in zip(workers(), devices())
	remotecall(device!, worker, gpu_dev)
    end
else
    addprocs(1; exeflags="--project")
end
@everywhere using QXContexts

# Load Simulation and contraction contexts
cg, _ = parse_dsl_files(dsl_file)
simctx = SimulationContext(param_file, cg, rank, comm_size)

@eval @everywhere workers() begin
    cg, _ = parse_dsl_files($dsl_file, $data_file)
    T = $using_cuda ? CuArray{$elt} : Array{$elt}
    conctx = QXContext{T}(cg)
end



#===================================================#
# Run Simulation
#===================================================#
@info "Rank $rank - Initialising work queues"
jobs_queue, amps_queue = start_queues(simctx) # <- this should spawn a feeder task

@info "Rank $rank - Starting contractors"
for worker in workers()
    remote_do((j, a) -> conctx(j, a), worker, jobs_queue, amps_queue)
end

@info "Rank $rank - Starting simulation"
results = simctx(amps_queue)



#===================================================#
# Collect results and clean up
#===================================================#
@info "Rank $rank - Collecting results"
results = collect_results(simctx, results, root, comm)
save_results(simctx, results, output_file)
rmprocs(workers())
