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
    dsl_file       = joinpath(file_path, "rqc/rqc_4_4_24.qx")
    parameter_file = joinpath(file_path, "rqc/rqc_4_4_24.yml")
    input_file     = joinpath(file_path, "rqc/rqc_4_4_24.jld2")
    output_file    = joinpath(file_path, "rqc/out.jld2")

    results = QXRun.execute(dsl_file, parameter_file, input_file, output_file, comm)
end

main(ARGS)