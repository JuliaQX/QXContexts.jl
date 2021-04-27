module Param

export parse_parameters

import YAML
using  DataStructures
using QXContexts.Sampling
import Base.Iterators: take

"""
    parse_parameters(filename::String;
                     max_parameters::Union{Int, Nothing}=nothing,
                     max_amplitudes::Union{Int, Nothing}=nothing)

Parse the parameters yml file to read information about partition parameters and their
dimensions as well as how the sampling of amplitudes will work.

Example Parameter file
======================
partitions:
    parameters:
        v1: 2
        v2: 2
        v3: 4
amplitudes:
  - "0000"
  - "0001"
  - "1111"

"""
function parse_parameters(filename::String;
                          max_parameters::Union{Int, Nothing}=nothing,
                          max_amplitudes::Union{Int, Nothing}=nothing)
    param_dict = YAML.load_file(filename, dicttype=OrderedDict{String, Any})

    # parse the paramters section of the parameter file
    partition_params = param_dict["partitions"]["parameters"]
    max_parameters = max_parameters === nothing ? length(partition_params) : max_parameters
    partition_params = OrderedDict{Symbol, Int}(Symbol(x[1]) => x[2] for x in take(partition_params, max_parameters))

    max_amplitudes === nothing || (param_dict["output"]["num_samples"] = max_amplitudes)
    sampler = construct_sampler(param_dict["output"])

    # return Parameters(amplitudes, variable_symbols, variable_values)
    return sampler, partition_params
end

end