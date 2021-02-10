module QXRun

using JLD

export execute

include("parameters.jl")
include("dsl.jl")
include("execution.jl")

using Requires
function __init__()
    @require MPI="da04e1cc-30fd-572f-bb4f-1f8673147195" include("mpi_execution.jl")
end

"""
    execute(dsl_file::String, param_file::String, input_file::String, output_file::String)

Run the commands in dsl_file, parameterised by the contents of param_file, with inputs
specified in input_file, and save the output(s) to output_file.
"""
function execute(dsl_file::String, param_file::String, input_file::String, output_file::String)
    if output_file == ""
        output_file = input_file
    end

    commands = parse_dsl(dsl_file)
    params = Parameters(param_file)

    ctx = QXContext(commands, params, input_file, output_file)

    results = execute!(ctx)

    JLD.save(output_file, "results", results)

    return results
end

end