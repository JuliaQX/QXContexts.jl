module LoggerTests

using Logging
using QXContexts.Logger
using Test
using Dates
using MPI

@testset "Logger Tests" begin
    original_logger = global_logger()
    try
        @testset "INFO test" begin
            io = IOBuffer()
            global_logger(QXLogger(; stream=io, show_info_source=true))
            @info "info_test"

            log = split(String(take!(io)), "\n")[1:end-1]
            df = DateFormat("[yyyy/mm/dd-HH:MM:SS.sss]");

            for l in log
                log_elem = split(l, " ")
                em = collect(eachmatch(r"\[(.*?)\]", log_elem[1])) # capture values in []
                @test DateTime(em[1].match, df) !== nothing
                @test em[2].match == "[host=$(gethostname())]"
                @test log_elem[2] == "INFO"
                @test log_elem[3] == "info_test"
            end
        end

        @testset "WARN test" begin
            io = IOBuffer()
            global_logger(QXLogger(; stream=io, show_info_source=true))

            @warn "warn_test"; line_num = @__LINE__

            log = split(String(take!(io)), "\n")[1:end-1]
            df = DateFormat("[yyyy/mm/dd-HH:MM:SS.sss]");

            for l in log
                log_elem = split(l, " ")
                em = collect(eachmatch(r"\[(.*?)\]", log_elem[1])) # capture values in []
                @test DateTime(em[1].match, df) !== nothing
                @test em[2].match == "[host=$(gethostname())]"
                @test log_elem[2] == "WARN"
                @test log_elem[3] == "warn_test"
                @test log_elem[4] == "-@->"
                file_line = splitext(log_elem[5])
                @test file_line[1] == splitext(@__FILE__)[1]
                @test split(file_line[2], ":")[2] == string(line_num)
            end
        end

        @testset "ERROR test" begin
            io = IOBuffer()
            global_logger(QXLogger(; stream=io, show_info_source=true))

            line_num = @__LINE__; @error "error_test"

            log = split(String(take!(io)), "\n")[1:end-1]
            df = DateFormat("[yyyy/mm/dd-HH:MM:SS.sss]");

            for l in log
                log_elem = split(l, " ")
                em = collect(eachmatch(r"\[(.*?)\]", log_elem[1])) # capture values in []
                @test DateTime(em[1].match, df) !== nothing
                @test em[2].match == "[host=$(gethostname())]"
                @test log_elem[2] == "ERROR"
                @test log_elem[3] == "error_test"
                @test log_elem[4] == "-@->"
                file_line = splitext(log_elem[5])
                @test file_line[1] == splitext(@__FILE__)[1]
                @test split(file_line[2], ":")[2] == string(line_num)
            end
        end

        @testset "MPI test" begin
            mktempdir() do path
                initialized = MPI.Initialized()
                initialized || MPI.Init()
                log_dir, time_log = get_log_path(path)
                logger = QXLogger(; log_dir=log_dir, time_log=time_log, show_info_source=true, root_path=path)
                global_logger(logger)
                @info "info_test"

                @test isfile(logger.log_path)
                log = readline(logger.log_path)
                df = DateFormat("[yyyy/mm/dd-HH:MM:SS.sss]");

                log_elem = split(log, " ")
                em = collect(eachmatch(r"\[(.*?)\]", log_elem[1])) # capture values in []
                @test DateTime(em[1].match, df) !== nothing
                @test em[2].match == "[host=$(gethostname())]"
                @test log_elem[2] == "INFO"
                @test log_elem[3] == "info_test"
                initialized || MPI.Finalize()
            end
        end
    finally
        global_logger(original_logger)
    end
end

end