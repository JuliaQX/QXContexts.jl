export parse_parameters, run_simulation

using Distributed
using CUDA
using Logging
using DataStructures
using ArgParse

import YAML

ArgParse.parse_item(::Type{DataType}, x::AbstractString) = getfield(Base, Symbol(x))

"""
    parse_parameters(filename::String;
                     max_parameters::Union{Int, Nothing}=nothing)

Parse the parameters yml file to read information about partition parameters and output 
sampling method.

Example Parameter file
======================
output:
  method: List
  params:
    bitstrings:
      - "01000"
      - "01110"
      - "10101"
"""
function parse_parameters(filename::String)
    param_dict = YAML.load_file(filename, dicttype=OrderedDict{String, Any})

    # parse the output method section of the parameter file
    method_params = OrderedDict{Symbol, Any}(Symbol(x[1]) => x[2] for x in param_dict["output"])
    method_params[:params] = OrderedDict{Symbol, Any}(Symbol(x[1]) => x[2] for x in method_params[:params])

    method_params
end

# TODO: Should copy MPI package for this and install in ~/.julia/bin
# https://juliaparallel.github.io/MPI.jl/latest/environment/#MPI.install_mpiexecjl
"""Place a copy of a simulation driver script in the given diretory"""
function generate_simulation_script(dir::String="./")
    file = joinpath(dirname(@__DIR__), "bin", "qxsimulate.jl")
    cp(file, joinpath(dir, "qxsimulate.jl"))
end

"""Initialise MPI and set up local julia cluster."""
function initialise_local_julia_cluster(using_cuda, log_dir, log_level)
    # Initialise mpi
    MPI.Init()
    comm = MPI.COMM_WORLD
    root = 0

    log_dir, time_log = get_log_path(log_dir)
    log_level = Logging.LogLevel(log_level)
    logger = QXLogger(; log_dir=log_dir, time_log=time_log, level=log_level)
    global_logger(logger)

    # Start up local Julia cluster
    initialise_worker_processes(using_cuda, log_dir, log_level)
    comm, root
end

"""Spawn worker processes and load the relevant packages."""
function initialise_worker_processes(using_cuda, log_dir, log_level)
  if using_cuda
      addprocs(length(devices()); exeflags="--project")
      @everywhere workers() eval(:(using CUDA))

      # Assign GPUs to worker processes
      for (worker, gpu_dev) in zip(workers(), devices())
        remotecall(device!, worker, gpu_dev)
      end
  else
      addprocs(1; exeflags="--project")
  end
  @everywhere workers() eval(:(using QXContexts))
  @everywhere workers() eval(:(using Logging))
  @eval @everywhere workers() logger = QXLogger(; log_dir=$log_dir, level=$log_level)
  @everywhere workers() global_logger(logger)
end