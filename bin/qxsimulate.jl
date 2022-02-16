using ArgParse
using MPI
using Distributed
using CUDA
using QXContexts
using Logging

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
        "--log-dir", "-l"
            help = "Directory for log files."
            default = "./"
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
    log_dir     = args["log-dir"]
    use_gpu     = args["gpu"]
    elt         = args["elt"]

    data_file  === nothing && (data_file  = splitext(dsl_file)[1] * ".jld2")
    param_file === nothing && (param_file = splitext(dsl_file)[1] * ".yml")
    start_time = time()

    #===================================================#
    # Initialise processes.
    #===================================================#
    # Initialise mpi
    MPI.Init()
    comm = MPI.COMM_WORLD
    root = 0
    
    log_dir = get_log_path(log_dir)
    logger = QXLogger(; log_dir=log_dir, level=Logging.Info)
    global_logger(logger)

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
    @everywhere workers() eval(:(using Logging))
    @eval @everywhere workers() logger = QXLogger(; log_dir=$log_dir, level=Logging.Info)
    @everywhere workers() global_logger(logger)


    #===================================================#
    # Initialise Contexts.
    #===================================================#
    @info "Setting up simulation context"
    cg, _ = parse_dsl_files(dsl_file)
    simctx = SimulationContext(param_file, cg, comm)

    @info "Setting up contraction context"
    expr = quote
        cg, _ = parse_dsl_files($dsl_file, $data_file)
        T = $using_cuda ? CuArray{$elt} : Array{$elt}
        conctx = QXContext{T}(cg)
    end
    @everywhere workers() eval($expr)


    #===================================================#
    # Start Simulation.
    #===================================================#
    @info "Initialising work queues"
    jobs_queue, amps_queue = start_queues(simctx)

    @info "Starting contractors"
    for worker in workers()
        remote_do((j, a) -> conctx(j, a), worker, jobs_queue, amps_queue)
    end

    @info "Starting simulation"
    results = simctx(amps_queue)


    #===================================================#
    # Collect results and clean up
    #===================================================#
    @info "Collecting results"
    results = collect_results(simctx, results, root, comm)
    save_results(simctx, results; output_file=output_file)
    rmprocs(workers())
    elapsed_time = time() - start_time
    open("qxtime.log", "a") do io
        time_report = "time:" * string(elapsed_time) * " "
        time_report *= join([string(k) * ":" * string(v) for (k, v) in pairs(args)], " ")
        time_report *= "\n"
        write(io, time_report)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end