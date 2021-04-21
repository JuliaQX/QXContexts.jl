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

    #TODO: Revise the way amplitudes are described
    amplitudes = unique([amplitude for amplitude in param_dict["amplitudes"]])
    if max_amplitudes !== nothing && length(amplitudes) > max_amplitudes
        amplitudes = amplitudes[1:max_amplitudes]
    end

    # parse the paramters section of the parameter file
    partition_params = param_dict["partitions"]["parameters"]
    max_parameters = max_parameters === nothing ? length(partition_params) : max_parameters
    partition_params = OrderedDict{Symbol, Int}(Symbol(x[1]) => x[2] for x in take(partition_params, max_parameters))
    # variables_symbols = [Symbol("\$$v") for v in take(keys(bond_info), max_parameters)]
    # variable_values = CartesianIndices(Tuple(take(values(bond_info), max_parameters)))

    # return Parameters(amplitudes, variable_symbols, variable_values)
    return amplitudes, partition_params
end

end