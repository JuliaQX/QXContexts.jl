using FileIO
using ArgParse

"""
    parse_commandline(ARGS)

Parse command line arguments and return argument dictionary
"""
function parse_commandline(ARGS)
    s = ArgParseSettings("QXContexts")

    @add_arg_table! s begin
        "input"
            help = "Input file to example"
            required = true
            arg_type = String        
    end
    return parse_args(ARGS, s)
end

"""
    main(ARGS)

QXContexts entry point
"""
function main(ARGS)
    args = parse_commandline(ARGS)

    input_file = args["input"]

    @show load(input_file)
end


if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end