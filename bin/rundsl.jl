using MPI
using QXRun
using ArgParse

"""
    parse_commandline(ARGS)

Parse command line arguments and return argument dictionary
"""
function parse_commandline(ARGS)
    s = ArgParseSettings("QXRun")

    @add_arg_table! s begin
        "--dsl", "-d"
            help = "DSL file path"
            required = true
            arg_type = String
        "--parameter-file", "-p"
            help = "Parameter file path"
            default = nothing
            arg_type = Union{Nothing, String}
        "--input", "-i"
            help = "Input data file path"
            required = true
            arg_type = String
        "--output", "-o"
            help = "Output data file path (defaults to input file)"
            default = nothing
            arg_type = Union{Nothing, String}
        "-v"
            help = "Enable verbose output"
            action = :count_invocations
    end

    return parse_args(ARGS, s)
end

"""
    main(ARGS)

QXRun entry point
"""
function main(ARGS)
    if !MPI.Initialized()
        MPI.Init()
    end
    comm = MPI.COMM_WORLD

    args = parse_commandline(ARGS)

    dsl_file       = args["dsl"]
    parameter_file = args["parameter-file"]
    input_file     = args["input"]
    output_file    = args["output"] === nothing ? input_file : args["output"]
    verbose        = args["v"]

    results = execute(dsl_file, parameter_file, input_file, output_file, comm)
end


if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end