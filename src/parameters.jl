import YAML

export Parameters, SubstitutionSet
export getindex


"""
    multi_index_partitions(partition_parameters::Vector{Dict{String, T}}) where T

Given an array of dictionaries containing a DSL variable bond size and it's maximum value,
construct a pair of return values containing:

1. The variable names
2. An array of tuples that contains each combination of values that the variables may take

Example
=======
```
julia> input = [Dict("v1" => 2), Dict("v2" => 4)];

julia> (names, values) = QXRun.multi_index_partitions(input)

(["v1", "v2"], [(1, 1), (2, 1), (1, 2), (2, 2), (1, 3), (2, 3), (1, 4), (2, 4)])
```
"""
function multi_index_partitions(partition_parameters::Vector{Dict{String, T}}) where T
    bond_sizes = []
    for bond_size in partition_parameters
        push!(bond_sizes, [k => v for (k, v) in bond_size]...)
    end

    bond_names = first.(bond_sizes)
    dims = Tuple(last.(bond_sizes))

    return (bond_names, CartesianIndices(dims))
end

"""
    Parameters(filename::String)

Representation of a DSL parameter file containing target amplitudes,
DSL variable names, and their corresponding values.

Example Parameter file
======================
partitions:
    parameters:
      - v1: 2
      - v2: 2
      - v3: 4
amplitudes:
  - "0000"
  - "0001"
  - "1111"

"""
struct Parameters
    amplitudes::Vector{String}
    symbols::Vector{Symbol}
    values::CartesianIndices
end

function Parameters(filename::String)
    data = YAML.load_file(filename, dicttype=Dict{String, Any})
    variable_symbols = Vector{Symbol}()

    amplitudes = [amplitude for amplitude in data["amplitudes"]]
    #TODO: handle regex-y states; e.g. "00**" => ["0000", "0001", "0010", "0011"]

    (variable_names, variable_values) = multi_index_partitions(data["partitions"]["parameters"])

    push!(variable_symbols, [Symbol("\$$v") for v in variable_names]...)

    return Parameters(amplitudes, variable_symbols, variable_values)
end

"""
Representation of a set of variables and their corresponding values
to be substituted into a parametric DSL command
"""
struct SubstitutionSet
    subs::Dict{Symbol, String}
    symbols::Vector{Symbol}
    values::CartesianIndices
end

function SubstitutionSet(amplitude::String, symbols::Vector{Symbol}, values::CartesianIndices)
    subs = Dict{Symbol, String}()

    # Generate substitutions for the amplitude values
    for i in 1:length(amplitude)
        subs[Symbol("\$o$i")] = "output_$(amplitude[i])"
    end

    return SubstitutionSet(subs, symbols, values)
end


import Base.length, Base.size
import Base.getindex
import Base.iterate

###############################################################################
# Parameter type interface
###############################################################################
length(p::Parameters) = length(p.amplitudes)
size(p::Parameters) = (length(p), length(p.values))

function getindex(data::Parameters, amplitude_index::Int)
    return SubstitutionSet(data.amplitudes[amplitude_index], data.symbols, data.values)
end

function getindex(data::Parameters, amplitude::String)
    if !(amplitude in data.amplitudes)
        throw(BoundsError(data, amplitude))
    end
    amplitude_index = findall(x -> x == amplitude, data.amplitudes)[1]
    return data[amplitude_index]
end

function iterate(p::Parameters, state::Int = 1)
    state > length(p) ? nothing : (p[state], state + 1)
end


###############################################################################
# SubstitutionSet type interface
###############################################################################
length(s::SubstitutionSet) = length(s.values)
size(s::SubstitutionSet) = (length(s),)

function getindex(s::SubstitutionSet, index::Int)
    if index > length(s.values)
        throw(BoundsError(s, index))
    else
        # Generate bindings for the remaining symbols and merge with the amplitude bindings
        return merge(s.subs, Dict{Symbol, String}(s.symbols .=> string.(Tuple(s.values[index]))))
    end
end

function iterate(s::SubstitutionSet, state::Int = 1)
    state > length(s.values) ? nothing : (s[state], state + 1)
end