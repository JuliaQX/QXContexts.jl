module Logger
# Follow approach taken by https://github.com/CliMA/Oceananigans.jl logger.jl

export QXLogger, QXLoggerMPIPerRank, QXLoggerMPIShared

using Logging
using Dates
using MPI
using TimerOutputs
import UUIDs: UUID, uuid4

import Logging: shouldlog, min_enabled_level, catch_exceptions, handle_message

const PerfLogger = Logging.LogLevel(-125)
const RankTimerLogger = Logging.LogLevel(-250)
const RankTimer = Logging.LogLevel(-50)

struct QXLogger <: Logging.AbstractLogger
    stream :: IO
    min_level :: Logging.LogLevel
    message_limits::Dict{Any,Int}
    show_info_source :: Bool
    session_id :: UUID
end

struct QXLoggerMPIShared <: Logging.AbstractLogger
    stream :: Union{MPI.FileHandle, Nothing}
    min_level :: Logging.LogLevel
    message_limits::Dict{Any,Int}
    show_info_source :: Bool
    session_id :: UUID
    comm ::MPI.Comm
end

struct QXLoggerMPIPerRank <: Logging.AbstractLogger
    stream :: Union{MPI.FileHandle, Nothing}
    min_level :: Logging.LogLevel
    message_limits::Dict{Any,Int}
    show_info_source :: Bool
    session_id :: UUID
    comm ::MPI.Comm
end


"""
    QXLogger(stream::IO=stdout, level=Logging.Info; show_info_source=false)

Single-process logger for QXRun.
"""
function QXLogger(stream::IO=stdout, level=Logging.Info; show_info_source=false)
    return QXLogger(stream, level, Dict{Any,Int}(), show_info_source, uuid4())
end

"""
    QXLoggerMPIShared(stream::MPI.FileHandle=MPI.File.open(comm, "qxrun_io.dat", read=true,  write=true, create=true), level=Logging.Info; show_info_source=false)

MPI-IO enabled logger that outputs to a single shared file for all ranks.
"""
function QXLoggerMPIShared(stream=nothing, level=Logging.Info; show_info_source=false, comm=MPI.COMM_WORLD)
    if MPI.Initialized()
        if MPI.Comm_rank(comm) == 0
            log_uid = uuid4()
        else
            log_uid = nothing
        end
        log_uid = MPI.bcast(log_uid, 0, comm)
        f_stream = MPI.File.open(comm, "qxrun_io_shared_$(log_uid).log", read=true,  write=true, create=true)
    else
        error("""MPI is required for this logger. Pleasure ensure MPI is initialised. Use `QXLogger` for non-distributed logging""")
    end
    return QXLoggerMPIShared(f_stream, level, Dict{Any,Int}(), show_info_source, log_uid, comm)
end

"""
    QXLoggerMPIPerRank(stream=nothing, level=Logging.Info; show_info_source=false, comm=MPI.COMM_WORLD)

MPI-friendly logger that outputs to a new file per rank. Creates a UUIDs.uuid4 labelled directory and a per-rank log-file
"""
function QXLoggerMPIPerRank(stream=nothing, level=Logging.Info; show_info_source=false, comm=MPI.COMM_WORLD)
    if MPI.Initialized()
        if MPI.Comm_rank(comm) == 0
            log_uid = uuid4()
        else
            log_uid = nothing
        end
        log_uid = MPI.bcast(log_uid, 0, comm)
    else
        throw("""MPI is required for this logger. Pleasure ensure MPI is initialised. Use `QXLogger` for non-distributed logging""")
    end
    return QXLoggerMPIPerRank(stream, level, Dict{Any,Int}(), show_info_source, log_uid, comm)
end

shouldlog(logger::QXLogger, level, _module, group, id) = get(logger.message_limits, id, 1) > 0
shouldlog(logger::QXLoggerMPIShared, level, _module, group, id) = get(logger.message_limits, id, 1) > 0
shouldlog(logger::QXLoggerMPIPerRank, level, _module, group, id) = get(logger.message_limits, id, 1) > 0

min_enabled_level(logger::QXLogger) = logger.min_level
min_enabled_level(logger::QXLoggerMPIShared) = logger.min_level
min_enabled_level(logger::QXLoggerMPIPerRank) = logger.min_level

catch_exceptions(logger::QXLogger) = false
catch_exceptions(logger::QXLoggerMPIShared) = false
catch_exceptions(logger::QXLoggerMPIPerRank) = false

function level_to_string(level)
    level == Logging.Error && return "ERROR"
    level == Logging.Warn  && return "WARN"
    level == Logging.Info  && return "INFO"
    level == Logging.Debug && return "DEBUG"
    level == PerfLogger && return "PERF"
    level == TimerLogger && return "TIMER"
    level == RankTimerLogger && return "RANKTIMERLOGGER"
    return string(level)
end

macro perf(expression)
    ex = repr(expression)
    return :(t = @elapsed res = $expression; Logging.@logmsg(PerfLogger, (t, $ex)); res)
end

macro timer(expression)
    ex = repr(expression)
    return :(t = @elapsed res = $expression; Logging.@logmsg(TimerLogger, (t, $ex)); res)
end

"""
    rank_log(rank, expression)

Enables logging of single or multiple selected ranks for function =evaluation elapsed time. 
Set rank to -1 to log all ranks
"""
macro rank_log(rank::Union{Int, Vector{Int}}, expression)
    if true === true
        ex = repr(expression)
        return :(t = @elapsed res = $expression; Logging.@logmsg(RankTimerLogger, (t, $ex)); res)
    else
        return esc(expression)
    end
end

"""
    stamp_builder(rank::Int)

Builds logger timestamp with rank and hostname capture.
Rank defaults to 0 for single-process evaluations
"""
function stamp_builder(rank::Int)
    io = IOBuffer()
    write(io, Dates.format(Dates.now(), "[yyyy/mm/dd-HH:MM:SS.sss]"))
    write(io, "[rank="*string(rank)*"]")
    write(io, "[host="*gethostname()*"]")
    s = String(take!(io))
    close(io)
    return s
end

function handle_message(logger::Union{QXLogger, QXLoggerMPIShared}, level, message, _module, group, id,
                                filepath, line; maxlog = nothing, kwargs...)           
    if !isnothing(maxlog) && maxlog isa Int
        remaining = get!(logger.message_limits, id, maxlog)
        logger.message_limits[id] = remaining - 1
        remaining > 0 || return nothing
    end

    buf = IOBuffer()
    level_name = level_to_string(level)
    if MPI.Initialized() && MPI.Comm_rank(MPI.COMM_WORLD) > 1
        rank = MPI.Comm_rank(logger.comm)
    else
        rank = 0
    end

    module_name = something(_module, "nothing")
    file_name   = something(filepath, "nothing")
    line_number = something(line, "nothing")
    msg_timestamp = stamp_builder(rank)

    formatted_message = "$(msg_timestamp) $(level_name) $message"
    if logger.show_info_source || level != Logging.Info
        formatted_message *= " $("-@->") $("$file_name:$line_number")"
    end
    formatted_message *= "\n"
    
    if typeof(logger.stream) <: IO 
        write(logger.stream,  formatted_message)
    else
        MPI.File.write_shared(logger.stream, formatted_message)
    end

    return nothing
end

function handle_message(logger::QXLoggerMPIPerRank, level, message, _module, group, id,
    filepath, line; maxlog = nothing, kwargs...)

    if !isnothing(maxlog) && maxlog isa Int
        remaining = get!(logger.message_limits, id, maxlog)
        logger.message_limits[id] = remaining - 1
        remaining > 0 || return nothing
    end

    if !isdir("qxrun_io_" * string(logger.session_id))
        mkdir("qxrun_io_" * string(logger.session_id))
    end

    buf = IOBuffer()
    rank = MPI.Comm_rank(logger.comm)
    level_name = level_to_string(level)

    file = open("qxrun_io_" * string(logger.session_id) * "/rank_" * "$(rank).log", read=true,  write=true, create=true, append=true)

    module_name = something(_module, "nothing")
    file_name   = something(filepath, "nothing")
    line_number = something(line, "nothing")
    msg_timestamp = stamp_builder(rank)

    formatted_message = "$(msg_timestamp) $(level_name) $message"
    if logger.show_info_source || level != Logging.Info
        formatted_message *= " $("-@->") $("$file_name:$line_number")"
    end
    formatted_message *= "\n"

    write(file, formatted_message)
    close(file)
    return nothing
end


end