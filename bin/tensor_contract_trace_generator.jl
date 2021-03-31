using MPI
using QXContexts
using TensorOperations
using OMEinsum
using Logging


"""
    tensor_opts(tensor_rank::Int64=8, enable_blas::Bool=true)

Generates random tensors of increasing rank to perform contractions with.
Generates increasing left and right tensors of increasing ranks, and contracts 
over a sliding window of indices. Will generate a rank 2*tensor_rank tensor at max.
"""
function tensor_opts(tensor_rank::Int=8)

    for idx_left in 0:tensor_rank
        t_left = randn(ComplexF32, ntuple(k->2, idx_left))
        t_label_left = Tuple(1:ndims(t_left))

        for idx_right in 0:tensor_rank
            t_right = randn(ComplexF32, ntuple(k->2, idx_right))

            for shift_idx in 0:idx_left
                t_label_right = Tuple((1:ndims(t_right)) .+ shift_idx)

                t_symdiff = Tuple(TensorOperations.symdiff(t_label_left, t_label_right))

                @info "Contracting L=$(t_label_left), R=$(t_label_right), OUT=$(t_symdiff) using EinCode"
                t = EinCode((t_label_left, t_label_right), t_symdiff)(t_left, t_right)

                t_hyper_list = intersect(t_label_left, t_label_right)

                for i in range(1,length(t_hyper_list),step=1)
                    t_hyper = Tuple(sort(vcat(collect(t_symdiff), t_hyper_list)))
                    @info "Contracting L=$(t_label_left), R=$(t_label_right), OUT=$(t_hyper), HYPER=$(t_hyper_list) using EinCode"
                    t = EinCode((t_label_left, t_label_right), t_hyper)(t_left, t_right)
                end
            end
        end
    end
    nothing;
end

"""
    tensor_opts_hyper(tensor_rank::Int64=8, enable_blas::Bool=true)

"""
function tensor_opts_hyper(tensor_rank::Int=8)

    for idx_left in 0:tensor_rank
        t_left = randn(ComplexF32, ntuple(k->2, idx_left))
        t_label_left = Tuple(1:ndims(t_left))

        for idx_right in 0:tensor_rank
            t_right = randn(ComplexF32, ntuple(k->2, idx_right))

            for shift_idx in 0:idx_left
                t_label_right = Tuple((1:ndims(t_right)) .+ shift_idx)

                t_symdiff = TensorOperations.symdiff(t_label_left, t_label_right)
                t_hyper_list = intersect(t_label_left,t_label_right)

                for i in range(1,length(t_hyper_list),step=1)
                    t_hyper = Tuple(sort(vcat(t_symdiff, t_hyper_list)))
                    @info "Contracting L=$(t_label_left), R=$(t_label_right), OUT=$(t_hyper) using EinCode"
                    t = EinCode((t_label_left, t_label_right), t_hyper )(t_left, t_right)
                end
            end
        end
    end
    nothing;
end



"""
    tensor_opts_fixed_rank(tensor_rank::Int=16)

Generates random tensors of decreasing rank to perform contractions with.
Never exceeds the given rank max, and will contract iteratively over ranged indices
"""
function tensor_opts_fixed_rank(tensor_rank::Int=16 )

    l_range = collect(1:16)

    for idx_left in tensor_rank:-1:1

        t_left = randn(ComplexF32, ntuple(k->2, idx_left))
        t_label_left = Tuple(l_range)

        r_range = collect(1:16)

        for idx_right in tensor_rank:-1:1

            t_right = randn(ComplexF32, ntuple(k->2, idx_right))
            t_label_right = Tuple(r_range)

            t_symdiff = Tuple(TensorOperations.symdiff(t_label_left, t_label_right))

            @info "Contracting L=$(t_label_left), R=$(t_label_right), OUT=$(t_symdiff) using EinCode"
            t = EinCode((t_label_left, t_label_right), t_symdiff)(t_left, t_right)
            
            popfirst!(r_range)
        end
        popfirst!(l_range)
    end
    nothing;
end

function main_func(args)
    enable_blas=true
    if !enable_blas
        TensorOperations.disable_blas()
    else
        TensorOperations.enable_blas()
    end

    if !MPI.Initialized()
        MPI.Init()
    end
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)

    tensor_opts(10) # 10 legs per tensor
    #tensor_opts_hyper(10) # 10 legs per tensor with hyper edges
    tensor_opts_fixed_rank(16) # max 16 leg tensor during contraction
end

# If executing as main
if abspath(PROGRAM_FILE) == @__FILE__
    main_func(ARGS)
end
