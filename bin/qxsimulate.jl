using ArgParse
using MPI
using Distributed
using CUDA
using QXContexts

# dsl_file = "../examples/ghz/ghz_5.qx"
# data_file = "../examples/ghz/ghz_5.jld2"
# param_file = "../examples/ghz/ghz_5_uniform.yml"
# output_file = "results.txt"

# elt = ComplexF32
# use_gpu = true
# num_cpu_workers = 1

function parse_commandline(ARGS)
    s = ArgParseSettings("QXContexts")

    @add_arg_table! s begin
        "--dsl", "-d"
            help = "DSL file path"
            required = true
            arg_type = String
        "--parameter-file", "-p"
            help = "Parameter file path, default is to use dsl filename with .yml suffix"
            default = nothing
            arg_type = String
        "--data-file", "-i"
            help = "Input data file path, default is to use dsl filename with .jld2 suffix"
            default = nothing
            arg_type = String
        "--output-file", "-o"
            help = "Output data file path"
            default = "qxsimulation_results.txt"
            arg_type = String
        "--gpu", "-g"
            help = "Use GPU if available"
            action = :store_true
        "--elt", "-e"
            help = "Element type to use for tensors"
            default = ComplexF32
            arg_type = DataType
    end
    return parse_args(ARGS, s)
end

function main(ARGS)
    args = parse_commandline(ARGS)
    dsl_file    = args["dsl"]
    data_file   = args["data-file"]
    param_file  = args["parameter-file"]
    output_file = args["output-file"]
    use_gpu     = args["gpu"]
    elt         = args["elt"]

    data_file  === nothing && (data_file  = splitext(dsl_file)[1] * ".jld2")
    param_file === nothing && (param_file = splitext(dsl_file)[1] * ".yml")

    #===================================================#
    # Initialise processes.
    #===================================================#
    # Initialise mpi ranks
    MPI.Init()
    comm = MPI.COMM_WORLD
    comm_size = MPI.Comm_size(comm)
    rank = MPI.Comm_rank(comm)
    root = 0

    # Start up local Julia cluster
    using_cuda = use_gpu && CUDA.functional() && !isempty(devices())
    if using_cuda
        addprocs(length(devices()); exeflags="--project")
        @everywhere workers() eval(:(using CUDA))

        # Assign GPUs to worker processes
        for (worker, gpu_dev) in zip(workers(), devices())
            remotecall(device!, worker, gpu_dev)
        end
    else
        addprocs(1; exeflags="--project")
    end
    @everywhere workers() eval(:(using QXContexts))


    #===================================================#
    # Initialise Contexts.
    #===================================================#
    cg, _ = parse_dsl_files(dsl_file)
    simctx = SimulationContext(param_file, cg, rank, comm_size)

    expr = quote
        cg, _ = parse_dsl_files($dsl_file, $data_file)
        T = $using_cuda ? CuArray{$elt} : Array{$elt}
        conctx = QXContext{T}(cg)
    end
    @everywhere workers() eval($expr)


    #===================================================#
    # Start Simulation.
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
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end