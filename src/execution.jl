export execute, initialise_sampler, timer_output

using FileIO
using TimerOutputs

using QXContexts.Param
using QXContexts.ComputeGraphs
using QXContexts.Sampling

const timer_output = TimerOutput()
if haskey(ENV, "QXRUN_TIMER")
    timeit_debug_enabled() = return true # Function fails to be defined by enable_debug_timings
    TimerOutputs.enable_debug_timings(Execution)
end

"""
    write_results(results, output_file)

Save results from calculations for the given
"""
function write_results(results, output_file)
    @assert splitext(output_file)[end] == ".jld2" "Output file should have jld2 suffix"
    if results !== nothing
        save(output_file, "results", results)
    end
end

"""
    initialise_sampler(dsl_file::String,
                       param_file::String,
                       input_file::String)

Initialise the sampler to
"""
function initialise_sampler(dsl_file::String,
                            param_file::String,
                            input_file::String)
    # read dsl file of commands and data file with initial tensors
    cg, _ = parse_dsl_files(dsl_file, input_file)

    # read sampler parameters from parameter file
    sampler_args = parse_parameters(param_file)

    # Create a context to execute the commands in
    ctx = QXContext(cg)

    # Create a sampler to produce bitstrings to get amplitudes for and a variable to store
    # the results.
    create_sampler(ctx, sampler_args)
end

"""
    execute(dsl_file::String,
            param_file::String,
            input_file::String,
            output_file::String="",
            max_amplitudes::Union{Int, Nothing}=nothing,
            max_slices::Union{Int, Nothing}=nothing)

Main entry point for running calculations. Loads input data, runs computations and
writes results to output files.
"""
function execute(dsl_file::String,
                 param_file::String,
                 input_file::String,
                 output_file::String="";
                 max_amplitudes::Union{Int, Nothing}=nothing,
                 max_slices::Union{Int, Nothing}=nothing)

    sampler = initialise_sampler(dsl_file, param_file, input_file)
    results = sampler(max_amplitudes=max_amplitudes, max_slices=max_slices)

    if output_file != "" write_results(results, output_file) end
    results
end