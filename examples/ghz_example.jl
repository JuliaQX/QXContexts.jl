using MPI
using QXRun
using Logging

"""
    main(ARGS)

QXRun entry point
"""
function main(args)
    if !MPI.Initialized()
        MPI.Init()
    end
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    
    if length(args) > 0 && args[1] === "3"
        global_logger(QXRun.Logger.QXLoggerMPIShared())
    elseif length(args) > 0 && args[1] === "2"
        global_logger(QXRun.Logger.QXLoggerMPIPerRank())
    else
        global_logger(QXRun.Logger.QXLogger())
    end

    file_path      = @__DIR__
    dsl_file       = file_path * "/ghz/ghz_5.tl"
    parameter_file = file_path * "/ghz/ghz_5.yml"
    input_file     = file_path * "/ghz/ghz_5.jld"
    output_file    = file_path * "/ghz/out.jld"

    results = QXRun.execute(dsl_file, parameter_file, input_file, output_file, comm)
end

main(ARGS)