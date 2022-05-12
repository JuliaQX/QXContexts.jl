using ArgParse
using Distributed
using CUDA
using QXContexts
using Logging


function parse_commandline(ARGS)
    s = ArgParseSettings("QXContexts")

    @add_arg_table! s begin
        "--dsl", "-d"
            help = "DSL file path."
            required = true
            arg_type = String
        "--parameter-file", "-p"
            help = "Parameter file path, default is to use dsl filename with .yml suffix."
            default = nothing
            arg_type = String
        "--data-file", "-i"
            help = "Input data file path, default is to use dsl filename with .jld2 suffix."
            default = nothing
            arg_type = String
        "--output-file", "-o"
            help = "Output data file path."
            default = "qxsimulation_results.txt"
            arg_type = String
        "--log-dir", "-l"
            help = "Directory for log files."
            default = "./"
            arg_type = String
        "--log-level"
            help = "Set the log level."
            default = 0
            arg_type = Integer
        "--gpu", "-g"
            help = "Use GPU if available."
            action = :store_true
        "--warm-up", "-w"
            help = "Run a warm up simulation before the main simaultion."
            action = :store_true
        "--elt", "-e"
            help = "Element type to use for tensors."
            default = ComplexF32
            arg_type = DataType
    end
    return parse_args(ARGS, s)
end

function run_simulation(
                        dsl_file,
                        data_file,
                        param_file,
                        output_file,
                        using_cuda, 
                        comm, 
                        root, 
                        elt;
                        save_output=true
                        )
    @info "Initialising simulation context"
    cg, _ = parse_dsl_files(dsl_file)
    simctx = SimulationContext(param_file, cg, comm, elt)

    @info "Initialising contraction contexts"
    expr = quote
        cg, _ = parse_dsl_files($dsl_file, $data_file)
        T = $using_cuda ? CuArray{$elt} : Array{$elt}
        conctx = QXContext{T}(cg)
    end
    @everywhere workers() eval($expr)

    @info "Initialising work queues"
    jobs_queue, amps_queue = start_queues(simctx)

    @info "Starting contractors"
    for worker in workers()
        remote_do((j, a) -> conctx(j, a), worker, jobs_queue, amps_queue)
    end

    @info "Starting simulation"
    results = simctx(amps_queue)

    @info "Collecting results"
    results = collect_results(simctx, results, root, comm)
    save_output && save_results(simctx, results; output_file=output_file)
end

function main(ARGS)
    args = parse_commandline(ARGS)
    dsl_file    = args["dsl"]
    data_file   = args["data-file"]
    param_file  = args["parameter-file"]
    output_file = args["output-file"]
    log_dir     = args["log-dir"]
    log_level   = args["log-level"]
    using_cuda  = args["gpu"] && CUDA.functional() && !isempty(devices())
    warm_up     = args["warm-up"]
    elt         = args["elt"]

    data_file  === nothing && (data_file  = splitext(dsl_file)[1] * ".jld2")
    param_file === nothing && (param_file = splitext(dsl_file)[1] * ".yml")
    time_log = ""

    # Set up and run the simulation.
    comm, root = QXContexts.initialise_local_julia_cluster(using_cuda, log_dir, log_level)
    if warm_up
        warm_up_time = @elapsed run_simulation(dsl_file, data_file, param_file, output_file, using_cuda, comm, root, elt; save_output=false)
        time_log *= "warm-up-time:$warm_up_time "
    end
    t = @elapsed run_simulation(dsl_file, data_file, param_file, output_file, using_cuda, comm, root, elt)

    # Clean up
    time_log *= "time:$t "
    @logmsg LogLevel(1) time_log args
    rmprocs(workers())
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
