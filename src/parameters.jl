import YAML

export Parameters, SubstitutionSet
export getindex
export num_qubits

"""
    Parameters(filename::String)

Representation of a DSL parameter file containing target amplitudes,
DSL variable names, and their corresponding values.

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
struct Parameters
    amplitudes::Vector{String}
    symbols::Vector{Symbol}
    values::CartesianIndices
end

function Parameters(filename::String)
    data = YAML.load_file(filename, dicttype=Dict{String, Any})
    variable_symbols = Vector{Symbol}()

    amplitudes = unique([amplitude for amplitude in data["amplitudes"]])
    #TODO: handle regex-y states; e.g. "00**" => ["0000", "0001", "0010", "0011"]

    bond_info = data["partitions"]["parameters"]
    variable_names = keys(bond_info)
    variable_values = CartesianIndices(Tuple(values(bond_info)))

    push!(variable_symbols, [Symbol("\$$v") for v in variable_names]...)

    return Parameters(amplitudes, variable_symbols, variable_values)
end

"""
Representation of a set of variables and their corresponding values
to be substituted into a parametric DSL command
"""
struct SubstitutionSet
    subs::Dict{Symbol, String}
    amplitude::String
    symbols::Vector{Symbol}
    values::CartesianIndices
end

function SubstitutionSet(amplitude::String, symbols::Vector{Symbol}, values::CartesianIndices)
    subs = Dict{Symbol, String}([
        Symbol("\$o$i") => "o$(i)_$ch" for (i, ch) in enumerate(amplitude)
    ])

    return SubstitutionSet(subs, amplitude, symbols, values)
end


import Base.length, Base.size
import Base.getindex
import Base.iterate
import Base.isequal

###############################################################################
# Parameter type interface
###############################################################################
length(p::Parameters) = length(p.amplitudes)
size(p::Parameters) = (length(p), length(p.values))

num_qubits(p::Parameters) = maximum(length.(p.amplitudes)) 

function getindex(data::Parameters, amplitude_index::Int)
    return SubstitutionSet(data.amplitudes[amplitude_index], data.symbols, data.values)
end

function getindex(data::Parameters, range::UnitRange{Int})
    return Parameters(data.amplitudes[range], data.symbols, data.values)
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

function isequal(x::Parameters, y::Parameters)
    same_amplitudes = sort(x.amplitudes) == sort(y.amplitudes)

    x_idx = sortperm(x.symbols)
    y_idx = sortperm(y.symbols)

    same_symbols = x.symbols[x_idx] == y.symbols[y_idx]

    same_values = x.values.indices[x_idx] == y.values.indices[y_idx]

    return same_amplitudes && same_symbols && same_values
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

function isequal(x::SubstitutionSet, y::SubstitutionSet)
    same_subs = x.subs == y.subs

    same_amplitudes = x.amplitude == y.amplitude

    x_idx = sortperm(x.symbols)
    y_idx = sortperm(y.symbols)

    same_symbols = x.symbols[x_idx] == y.symbols[y_idx]

    same_values = x.values.indices[x_idx] == y.values.indices[y_idx]

    return same_subs && same_amplitudes && same_symbols && same_values
end