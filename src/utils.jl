export parse_parameters

import YAML
using  DataStructures

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

function generate_simulation_script(dir::String="./")
  file = joinpath(dirname(@__DIR__), "bin", "qxsimulate.jl")
  cp(file, joinpath(dir, "qxsimulate.jl"))
end