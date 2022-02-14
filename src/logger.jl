module Logger
# Follow approach taken by https://github.com/CliMA/Oceananigans.jl logger.jl

using Logging
using Dates
using MPI
using TimerOutputs
import Distributed: myid
import UUIDs: UUID, uuid4
import Logging: shouldlog, min_enabled_level, catch_exceptions, handle_message

export QXLogger, get_log_path

const PerfLogger = Logging.LogLevel(-125)

macro perf(expression)
    if haskey(ENV, "QXRUN_TIMER")
        ex = repr(expression)
        return :(t = @elapsed res = $expression; Logging.@logmsg(PerfLogger, (t, $ex)); res)
    else
        return esc(expression)
    end
end

#======================================================================#
# QXContexts Logger
#======================================================================#

struct QXLogger <: Logging.AbstractLogger
    stream::Union{IO, Nothing}
    min_level::Logging.LogLevel
    message_limits::Dict{Any,Int}
    show_info_source::Bool
    log_path::Union{String, Nothing}
end

"""
    QXLogger(stream::IO=stdout, level=Logging.Info; show_info_source=false)

Logger for QXContexts.
"""
function QXLogger(;log_dir=nothing, stream=nothing, level=Logging.Info, show_info_source=false, root_path="./")
    log_path = nothing
    if stream === nothing
        log_dir == "" && (log_dir = get_log_path(root_path))
        log_path = joinpath(log_dir, "proc_$(myid()).log")
        # stream = open(log_path, "w+")
    end
    QXLogger(stream, level, Dict{Any,Int}(), show_info_source, log_path)
end

shouldlog(logger::QXLogger, level, _module, group, id) = get(logger.message_limits, id, 1) > 0
min_enabled_level(logger::QXLogger) = logger.min_level
catch_exceptions(logger::QXLogger) = false

function handle_message(logger::QXLogger, level, message, _module, group, id,
                        filepath, line; maxlog = nothing, kwargs...)
    if !isnothing(maxlog) && maxlog isa Int
        remaining = get!(logger.message_limits, id, maxlog)
        logger.message_limits[id] = remaining - 1
        remaining > 0 || return nothing
    end

    level_name = level_to_string(level)
    msg_timestamp = stamp_builder()

    formatted_message = "$(msg_timestamp) $(level_name) $message"
    if logger.show_info_source || level != Logging.Info
        formatted_message *= " -@-> $(filepath):$(line)"
    end
    formatted_message *= "\n"
    if logger.log_path === nothing
        stream = logger.stream
        write(stream, formatted_message)
    else
        stream = open(logger.log_path, "a+")
        write(stream, formatted_message)
        close(stream)
    end
    nothing
end

#======================================================================#
# Convenience Functions
#======================================================================#

function level_to_string(level)
    level == Logging.Error && return "ERROR"
    level == Logging.Warn  && return "WARN"
    level == Logging.Info  && return "INFO"
    level == Logging.Debug && return "DEBUG"
    level == PerfLogger && return "PERF"
    return string(level)
end

"""
    stamp_builder(rank::Int)

Builds logger timestamp with rank and hostname capture.
Rank defaults to 0 for single-process evaluations
"""
function stamp_builder()
    io = IOBuffer()
    write(io, Dates.format(Dates.now(), "[yyyy/mm/dd-HH:MM:SS.sss]"))
    write(io, "[host="*gethostname()*"]")
    s = String(take!(io))
    close(io)
    return s
end

function get_log_path(root_path="./")
    if MPI.Initialized()
        comm = MPI.COMM_WORLD
        rank = MPI.Comm_rank(comm)
        log_uid = rank == 0 ? uuid4() : nothing
        log_uid = MPI.bcast(log_uid, 0, comm)
        log_dir = joinpath(root_path, "QXContexts_io_" * string(log_uid))
        !isdir(log_dir) && mkdir(log_dir)
        log_dir = joinpath(log_dir, "rank_$(rank)")
        !isdir(log_dir) && mkdir(log_dir)
        return log_dir
    else
        error("MPI must be initialized to use QXLogger with the default stream.")
    end
end

end