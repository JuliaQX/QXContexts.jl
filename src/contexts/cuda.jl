
""""Macro which adds NVTX range only if CUDA is functional"""
macro nvtx_range(label, ex)
    if CUDA.functional()
        return quote
            NVTX.@range $(esc(label)) $(esc(ex))
        end
    else
        return quote
            $(esc(ex))
        end
    end
end