# using MPI
using QXContexts
using ArgParse

"""
    parse_commandline(ARGS)

Parse command line arguments and return argument dictionary
"""
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
        "--input-file", "-i"
            help = "Input data file path, default is to use dsl filename with .jld2 suffix"
            default = nothing
            arg_type = String
        "--output-file", "-o"
            help = "Output data file path"
            required = true
            arg_type = String
        "--number-amplitudes", "-a"
            help = "Number of amplitudes to calculate out of number in parameter file"
            default = nothing
            arg_type = Int
        "--number-slices", "-n"
            help = "The number of slices to use out of number given in parameter file"
            default = nothing
            arg_type = Int
        # "--sub-communicator-size", "-m"
        #     help = "The number of ranks to assign to each sub-communicator for partitions"
        #     default = 1
        #     arg_type = Int
        "-v"
            help = "Enable verbose output"
            action = :count_invocations
    end
    return parse_args(ARGS, s)
end

"""
    main(ARGS)

QXContexts entry point
"""
function main(ARGS)
    # if !MPI.Initialized()
        # MPI.Init()
    # end
    # comm = MPI.COMM_WORLD

    args = parse_commandline(ARGS)

    dsl_file       = args["dsl"]
    parameter_file = args["parameter-file"]
    input_file     = args["input-file"]
    output_file    = args["output-file"]
    number_amplitudes = args["number-amplitudes"]
    number_slices  = args["number-slices"]
    # sub_comm_size  = args["sub-communicator-size"]
    verbose        = args["v"]

    # if parameter file and/or input file not given assume same name
    # as dsl with appropriate suffix
    if parameter_file === nothing
        parameter_file = splitext(dsl_file)[1] * ".yml"
    end
    if input_file === nothing
        input_file = splitext(dsl_file)[1] * ".jld2"
    end
    results = execute(dsl_file,
                      parameter_file,
                      input_file,
                      output_file,
                      max_amplitudes=number_amplitudes,
                      max_slices=number_slices)
end


if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end