module Param

export parse_parameters

import YAML
using  DataStructures
import Base.Iterators: take

"""
    parse_parameters(filename::String;
                     max_parameters::Union{Int, Nothing}=nothing)

Parse the parameters yml file to read information about partition parameters and output 
sampling method.

Example Parameter file
======================
partitions:
  parameters:
    v1: 2
    v2: 2
output:
  method: List
  params:
    bitstrings:
      - "01000"
      - "01110"
      - "10101"
"""
function parse_parameters(filename::String;
                          max_parameters::Union{Int, Nothing}=nothing)
    param_dict = YAML.load_file(filename, dicttype=OrderedDict{String, Any})

    # parse the partition paramters section of the parameter file
    partition_params = param_dict["partitions"]["parameters"]
    max_parameters = max_parameters === nothing ? length(partition_params) : max_parameters
    partition_params = OrderedDict{Symbol, Int}(Symbol(x[1]) => x[2] for x in take(partition_params, max_parameters))

    # parse the output method section of the parameter file
    method_params = OrderedDict{Symbol, Any}(Symbol(x[1]) => x[2] for x in param_dict["output"])
    method_params[:params] = OrderedDict{Symbol, Any}(Symbol(x[1]) => x[2] for x in method_params[:params])

    return method_params, partition_params
end

end