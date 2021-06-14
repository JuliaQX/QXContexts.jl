using Logging
using ArgParse
using MPI

using QXContexts

"""
    main(ARGS)

QXContexts entry point
"""
function main(args)
    s = ArgParseSettings("QXContexts")
    @add_arg_table! s begin
        "--sub-comm-size", "-s"
            help = "The number of ranks to assign to each sub-communicator for partitions"
            default = 1
            arg_type = Int
        "--mpi", "-m"
            help = "Use MPI"
            action = :store_true
        "--gpu", "-g"
            help = "Use GPU if available"
            action = :store_true
        "--verbose", "-v"
            help = "Enable logging"
            action = :store_true
    end
    parsed_args = parse_args(args, s)

    if parsed_args["verbose"]
        if parsed_args["mpi"]
            if !MPI.Initialized() MPI.Init() end
            global_logger(QXContexts.Logger.QXLoggerMPIPerRank())
        else
            global_logger(QXContexts.Logger.QXLogger())
        end
    end

    file_path      = @__DIR__
    dsl_file       = joinpath(file_path, "rqc/rqc_4_4_24.qx")
    param_file = joinpath(file_path, "rqc/rqc_4_4_24.yml")
    input_file     = joinpath(file_path, "rqc/rqc_4_4_24.jld2")
    output_file    = joinpath(file_path, "rqc/out.jld2")

    results = execute(dsl_file, input_file, param_file, output_file;
                      use_mpi=parsed_args["mpi"],
                      sub_comm_size=parsed_args["sub-comm-size"],
                      use_gpu=parsed_args["gpu"])
    if parsed_args["verbose"]
        @info results
    end
end

main(ARGS)