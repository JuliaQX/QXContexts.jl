# """
# Functions for optmising tree
# """
# """
#     permute_and_merge!(node::ComputeNode, new_index_order=nothing)

# Descend contraction tree simplifying contraction commands by permuting and merging together
# indices so that contractions operations are more efficient. When not a contraciton or reshape
# node we can ignore and pass ordering on.
# """
# function permute_and_merge!(node::ComputeNode, new_index_order=nothing)
#     permute_and_merge!.(node.children, [new_index_order])
#     nothing
# end

# """
#     permute_and_merge!(node::ComputeNode{ReshapeCommand}, new_index_order=nothing)

# Descend contraction tree simplifying contraction commands by permuting and merging together
# indices so that contractions operations are more efficient. For a reshape command, modify
# the index ordering to apply to indices pre-reshape operation.
# """
# function permute_and_merge!(node::ComputeNode{ReshapeCommand}, new_index_order=nothing)
#     if new_index_order !== nothing
#
#     end
#     permute_and_merge!.(node.children, [new_index_order])
#     nothing
# end


# """
#     permute_and_merge!(node::ComputeNode{ContractCommand}, new_index_order=nothing)

# Descend contraction tree simplifying contraction commands by permuting and merging together
# indices so that contractions operations are more efficient.

# For example, when there are a sequence of contractions like
# ````
# ncon c 1,2,3,4 a 1,2,3,4 b 0
# ncon e 1,2,3,4 d 1,2,3,4 e 0
# ncon f 1,4,5,6 c 1,2,3,4 e 5,6,3,2
# ```
# in the last contraction indices 2,3 are contracted and thus can be merged. We first permute as
# ```
# ncon d 1,4,5,6 c 2,3,1,4 e 2,3,5,6
# ```
# and then joining (2,3) => 2 which gives
# ```
# ncon ncon d 1,4,5,6 c 2,1,4 e 2,5,6
# ```
# This would require previous commands to be changed so full set would be
# ````
# ncon c (2,3),1,4 a 1,2,3,4 b 0
# ncon e (4,3),1,2 d 1,2,3,4 e 0
# ncon f 1,4,5,6 c 2,1,4 e 2,5,6
# ```
# where the parentheses indicate that these indices should be merged. To achieve the above open
# would send the following new_index_order arrays to left and right children.
# Left: [[2, 3], 1, 4]
# Right: [[4, 3], 1 ,2]

# Additionally, any indices appearing in all three tuples should be moved to the end.
# In this case we would have a recursive process which passes down indices list
# """
# function permute_and_merge!(node::ComputeNode{ContractCommand}, new_index_order=nothing)
#     _permute_and_merge!(node.data, new_index_order)

#     # identify batched, common and remaining indices
#     batch_idxs = batched_indices(node.data) # these go at the end
#     common_idxs = setdiff(intersect(node.data.left_idxs, node.data.right_idxs), batch_idxs) # these go at the start in order appear in left
#     # we choose to order by the highest rank child
#     if length(node.data.right_idxs) > length(node.data.left_idxs)
#         common_idxs = filter(x -> x in common_idxs, node.data.right_idxs) # ensure it's ordered by right idxs
#     else
#         common_idxs = filter(x -> x in common_idxs, node.data.left_idxs) # ensure it's ordered by left idxs
#     end
#     remaining_idxs = setdiff(union(node.data.left_idxs, node.data.right_idxs), union(common_idxs, batch_idxs)) # these go in the middle
#     remaining_idxs = filter(x -> x in remaining_idxs, node.data.output_idxs) # reorder by output

#     if isdefined(node, :left)
#         l_index_map = Dict(x => i for (i, x) in enumerate(node.data.left_idxs))
#         m = x -> [l_index_map[y] for y in x]
#         left_remaining_idxs = filter(x -> x in node.data.left_idxs, remaining_idxs)
#         # left_remaining_idx_groups = find_overlaps(node.data.output_idxs, left_remaining_idxs)
#         new_index_order = length(common_idxs) == 0 ? Vector{Vector{Int}}() : [m(common_idxs)]
#         append!(new_index_order, [map(x -> [x], m(left_remaining_idxs))..., map(x -> [x], m(batch_idxs))...])
#         # append!(new_index_order, [m.(left_remaining_idx_groups)..., map(x -> [x], m(batch_idxs))...])
#         # @show left_remaining_idxs, remaining_idxs
#         permute_and_merge!(node.left, new_index_order)
#         new_left_idxs = length(common_idxs) > 0 ? [common_idxs[1]] : Int[]
#         append!(new_left_idxs, [left_remaining_idxs..., batch_idxs...])
#         empty!(node.data.left_idxs)
#         append!(node.data.left_idxs, new_left_idxs)
#     end
#     if isdefined(node, :right)
#         r_index_map = Dict(x => i for (i, x) in enumerate(node.data.right_idxs))
#         m = x -> [r_index_map[y] for y in x]
#         right_remaining_idxs = filter(x -> x in node.data.right_idxs, remaining_idxs)
#         # right_remaining_idx_groups = find_overlaps(node.data.output_idxs, right_remaining_idxs)
#         new_index_order = length(common_idxs) == 0 ? Vector{Vector{Int}}() : [m(common_idxs)]
#         append!(new_index_order, [map(x -> [x], m(right_remaining_idxs))..., map(x -> [x], m(batch_idxs))...])
#         # append!(new_index_order, [m.(right_remaining_idx_groups)..., map(x -> [x], m(batch_idxs))...])
#         permute_and_merge!(node.right, new_index_order)
#         new_right_idxs = length(common_idxs) > 0 ? [common_idxs[1]] : Int[]
#         append!(new_right_idxs, [right_remaining_idxs..., batch_idxs...])
#         empty!(node.data.right_idxs)
#         append!(node.data.right_idxs, new_right_idxs)
#     end
#     nothing
# end

# batched_indices(cmd) = intersect(cmd.output_idxs, cmd.left_idxs, cmd.right_idxs)

# function _permute_and_merge!(cmd::ContractCommand, new_index_order)
#     if new_index_order !== nothing
#         # get mapping between indices as seen by next command, ordered 1,2..n where n is rank
#         # and grouped according to reshape_groups
#         current_idxs = Dict{Int, Vector{Int}}()
#         pos = 1
#         for (i, group_size) in enumerate(cmd.reshape_groups)
#             current_idxs[i] = cmd.output_idxs[pos:pos+group_size-1]
#             pos += group_size
#         end
#         flat_order = vcat(new_index_order...)
#         # @show cmd.output_name, new_index_order
#         # @show cmd.output_idxs, vcat(map(x -> current_idxs[x], flat_order)...)
#         cmd.output_idxs[:] = vcat(map(x -> current_idxs[x], flat_order)...)
#         # update reshape groups to reflect any new merges
#         new_reshape_groups = []
#         pos = 1
#         for l in length.(new_index_order)
#             push!(new_reshape_groups, sum(cmd.reshape_groups[pos:pos+l-1]))
#             pos += l
#         end
#         empty!(cmd.reshape_groups)
#         append!(cmd.reshape_groups, new_reshape_groups)
#     end
# end

# """
#     join_remaining!(node::ComputeNode{ContractCommand}, new_index_order=nothing)

# Identify groups of indices that are grouped in the output indices and also appear in the same
# order in the left and right index groups. Merge these in left and right index groups and pass
# this grouping to children

# Example:

# """
# function join_remaining!(node::ComputeNode{ContractCommand}, new_index_order=nothing)
#     _join_remaining!(node.data, new_index_order)

#     # find output indices that are merged in the reshape after the contraction
#     pos = 1
#     output_groups = Vector{Vector{Int}}()
#     for j in node.data.reshape_groups
#         push!(output_groups, node.data.output_idxs[pos:pos+j-1])
#         pos += j
#     end

#     # identify batched, common and remaining indices
#     batch_idxs = batched_indices(node.data) # these go at the end
#     common_idxs = setdiff(intersect(node.data.left_idxs, node.data.right_idxs), batch_idxs) # these go at the start in order appear in left
#     common_idxs = filter(x -> x in common_idxs, node.data.left_idxs) # ensure it's ordered by left idxs
#     remaining_idxs = setdiff(union(node.data.left_idxs, node.data.right_idxs), union(common_idxs, batch_idxs)) # these go in the middle
#     remaining_idxs = filter(x -> x in remaining_idxs, node.data.output_idxs) # reorder by output

#     if isdefined(node, :left)
#         l_index_map = Dict(x => i for (i, x) in enumerate(node.data.left_idxs))
#         m = x -> [l_index_map[y] for y in x]
#         left_remaining_idxs = filter(x -> x in node.data.left_idxs, remaining_idxs)
#         left_remaining_idx_groups = find_overlaps(output_groups, left_remaining_idxs)

#         # we join these in the output idxs
#         join_output_idxs!(node.data, left_remaining_idx_groups)

#         # we replace each index with it's possition and then call join_remaing on node
#         new_index_order = length(common_idxs) == 0 ? Vector{Vector{Int}}() : [m(common_idxs)]
#         append!(new_index_order, [m.(left_remaining_idx_groups)..., map(x -> [x], m(batch_idxs))...])
#         join_remaining!(node.left, new_index_order)

#         new_left_idxs = length(common_idxs) > 0 ? [common_idxs[1]] : Int[]
#         append!(new_left_idxs, [map(x -> x[1], left_remaining_idx_groups)..., batch_idxs...])
#         empty!(node.data.left_idxs)
#         append!(node.data.left_idxs, new_left_idxs)
#     end
#     if isdefined(node, :right)
#         r_index_map = Dict(x => i for (i, x) in enumerate(node.data.right_idxs))
#         m = x -> [r_index_map[y] for y in x]
#         right_remaining_idxs = filter(x -> x in node.data.right_idxs, remaining_idxs)
#         right_remaining_idx_groups = find_overlaps(output_groups, right_remaining_idxs)

#         # we join these in the output idxs
#         join_output_idxs!(node.data, right_remaining_idx_groups)

#         # we replace each index with it's possition and then call join_remaing on node
#         new_index_order = length(common_idxs) == 0 ? Vector{Vector{Int}}() : [m(common_idxs)]
#         append!(new_index_order, [m.(right_remaining_idx_groups)..., map(x -> [x], m(batch_idxs))...])
#         join_remaining!(node.right, new_index_order)

#         new_right_idxs = length(common_idxs) > 0 ? [common_idxs[1]] : Int[]
#         append!(new_right_idxs, [map(x -> x[1], right_remaining_idx_groups)..., batch_idxs...])
#         empty!(node.data.right_idxs)
#         append!(node.data.right_idxs, new_right_idxs)
#     end
#     nothing
# end

# function _join_remaining!(cmd::ContractCommand, new_index_order)
#     if new_index_order !== nothing
#         # get mapping between indices as seen by next command, ordered 1,2..n where n is rank
#         # and grouped according to reshape_groups
#         current_idxs = Dict{Int, Vector{Int}}()
#         pos = 1
#         for (i, group_size) in enumerate(cmd.reshape_groups)
#             current_idxs[i] = cmd.output_idxs[pos:pos+group_size-1]
#             pos += group_size
#         end
#         flat_order = vcat(new_index_order...)
#         cmd.output_idxs[:] = vcat(map(x -> current_idxs[x], flat_order)...)
#         # update reshape groups to reflect any new merges
#         new_reshape_groups = []
#         pos = 1
#         for l in length.(new_index_order)
#             push!(new_reshape_groups, sum(cmd.reshape_groups[pos:pos+l-1]))
#             pos += l
#         end
#         empty!(cmd.reshape_groups)
#         append!(cmd.reshape_groups, new_reshape_groups)
#     end
# end

# """
#     find_overlaps(arrays::Vector{<: Vector{T}}, sub_array::Vector{T}) where T

# Given a set of arrays and a single sub array, this function will return subsets
# of the sub_array which appear in sequence next to each other

# Example:
# arrays: [[1,2,3], [8,9,12,14]]
# sub_array: [1,2,9,12,13,14]

# should return
# [[1,2],[9,12],[14]]
# """
# function find_overlaps(arrays::Vector{<: Vector{T}}, sub_array::Vector{T}) where T
#     sub_pos = 1
#     groups = Vector{Vector{T}}()
#     while sub_pos <= length(sub_array)
#         array_pos = findfirst(x -> sub_array[sub_pos] in x, arrays)
#         if array_pos !== nothing
#             array = arrays[array_pos]
#             pos = findfirst(x -> x == sub_array[sub_pos], array)
#             i = 1
#             while pos + i <= length(array) &&
#                 sub_pos + i <= length(sub_array) &&
#                 array[pos+i] == sub_array[sub_pos+i]
#                 i += 1
#             end
#             push!(groups, sub_array[sub_pos:sub_pos+i-1])
#         else i = 1 end
#         sub_pos += i
#     end
#     groups
# end

# """
#     group_elements(group_sizes::Vector{Int}, elements::Vector)

# Function to group elements in a vector according to given group sizes
# """
# function group_elements(group_sizes::Vector{Int}, elements::Vector)
#     pos = 1
#     @assert sum(group_sizes) == length(elements) "Sum of group sizes should match vector length"
#     groups = Vector{Vector{eltype(elements)}}()
#     for j in group_sizes
#         push!(groups, elements[pos:pos+j-1])
#         pos += j
#     end
#     groups
# end


# """
#     join_output_idxs!(cmd::ContractCommand, groups)

# Given a list of groups of indices we can replace these groups in the output
# index set with the first index in each group. We also update the reshape
# groups to take this into account

# Example:
# --------
# output_idxs: 4,5,2,1
# reshape_groups: 3,1
# groups: [[4,5],[2],[1]]

# expected output:
# ----------------
# output_idxs: 4,2,1
# reshape_groups: 2,1
# """
# function join_output_idxs!(cmd::ContractCommand, groups)
#     output_groups = group_elements(cmd.reshape_groups, cmd.output_idxs)

#     for group in groups
#         if length(group) > 1
#             # find relevant output group
#             output_group_idx = findfirst(x -> length(intersect(x, group)) > 0, output_groups)
#             # replace indices in this group with first element
#             output_group = output_groups[output_group_idx]
#             pos = findfirst(x -> x == group[1], output_group)
#             for _ in 1:length(group)-1 popat!(output_group, pos+1) end
#         end
#     end

#     empty!(cmd.output_idxs)
#     append!(cmd.output_idxs, vcat(output_groups...))
#     empty!(cmd.reshape_groups)
#     append!(cmd.reshape_groups, length.(output_groups))
# end