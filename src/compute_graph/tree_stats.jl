export cost, max_degree, depth, balance

indices(c::ContractCommand) = c.left_idxs, c.right_idxs, c.output_idxs

cost(c::AbstractCommand) = 0

"""
    cost(cmd::ContractCommand)::Number

Function to calculate the cost of the given contraction in FLOPS
"""
function cost(cmd::ContractCommand)::Number
    a, b, c = indices(cmd)
    batched_idxs = intersect(a, b, c)
    a = setdiff(a, batched_idxs)
    b = setdiff(b, batched_idxs)
    c = setdiff(c, batched_idxs)
    common = intersect(a, b)
    remaining = symdiff(a, b)
    1 << (length(common) + length(remaining) + length(batched_idxs))
end

max_degree(c::ContractCommand) = maximum(length.(indices(c)))
cost(n::ComputeNode) = cost(n.op) + sum(cost.(children(n)), init=0)
max_degree(n::ComputeNode) = maximum(max_degree.(children(n)), init=0)
max_degree(n::ComputeNode{ContractCommand}) = maximum([max_degree(n.op), max_degree.(children(n))...])
depth(n::ComputeNode) = 1 + maximum(depth.(children(n)), init=0)
Base.length(n::ComputeNode) = 1 + sum(length.(children(n)), init=0)
balance(n::ComputeNode) = ceil(log2(length(n)))/depth(n)

"""Implement show for compute node to display some useful metrics"""
function Base.show(io::IO, c::ComputeNode{T}) where T
    print(io, "ComputeNode{$(T)}: children: $(length(c)-1), ",
              "depth: $(depth(c)), balance: $(balance(c)), ",
              "max_degree: $(max_degree(c))")
end