export execute, initialise_sampler, timer_output

using FileIO
using TimerOutputs
using CUDA

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
                       input_file::String,
                       param_file::String;
                       use_mpi::Bool=false,
                       sub_comm_size::Int=1,
                       use_gpu::Bool=false,
                       elt::Type=ComplexF32)

Initialise the sampler
"""
function initialise_sampler(dsl_file::String,
                            input_file::String,
                            param_file::String;
                            use_mpi::Bool=false,
                            sub_comm_size::Int=1,
                            use_gpu::Bool=false,
                            elt::Type=ComplexF32)
    # read dsl file of commands and data file with initial tensors
    cg, _ = parse_dsl_files(dsl_file, input_file)

    # Create a context to execute the commands in
    T = if use_gpu
        @assert CUDA.functional() "CUDA installation is not functional, ensure you have a GPU and appropriate drivers"
        CuArray{elt}
    else
        Array{elt}
    end
    ctx = QXContext{T}(cg)
    if use_mpi
        ctx = QXMPIContext(ctx, sub_comm_size=sub_comm_size)
    end

    # read sampler parameters from parameter file
    sampler_args = parse_parameters(param_file)

    # Create a sampler to produce bitstrings to get amplitudes for and a variable to store
    # the results.
    create_sampler(ctx, sampler_args)
end

"""
    execute(dsl_file::String,
            input_file::Union{String, Nothing}=nothing,
            param_file::Union{String, Nothing}=nothing,
            output_file::String="";
            max_amplitudes::Union{Int, Nothing}=nothing,
            max_slices::Union{Int, Nothing}=nothing,
            kwargs...)

Main entry point for running calculations. Loads input data, runs computations and
writes results to output files.
"""
function execute(dsl_file::String,
                 input_file::Union{String, Nothing}=nothing,
                 param_file::Union{String, Nothing}=nothing,
                 output_file::String="";
                 max_amplitudes::Union{Int, Nothing}=nothing,
                 max_slices::Union{Int, Nothing}=nothing,
                 kwargs...)

    if input_file === nothing
        input_file = splitext(dsl_file)[1] * ".jld2"
    end

    if param_file === nothing
        param_file = splitext(dsl_file)[1] * ".yml"
    end
    sampler = initialise_sampler(dsl_file, input_file, param_file;
                                 kwargs...)

    results = sampler(max_amplitudes=max_amplitudes,
                      max_slices=max_slices)

    if output_file != "" && results !== nothing
        write_results(results, output_file)
    end
    results
end
