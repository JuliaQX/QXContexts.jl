module LoggerTests

using Logging
using QXContexts.Logger
using Test
using Dates
using MPI

@testset "Logger Tests" begin
    @testset "QXLogger" begin
        @testset "INFO test" begin
            io = IOBuffer()
            global_logger(QXLogger(io; show_info_source=true))
            @info "info_test"

            log = split(String(take!(io)), "\n")[1:end-1]
            df = DateFormat("[yyyy/mm/dd-HH:MM:SS.sss]");

            for l in log
                log_elem = split(l, " ")
                em = collect(eachmatch(r"\[(.*?)\]", log_elem[1])) # capture values in []
                @test DateTime(em[1].match, df) !== nothing
                @test match(r"[rank=/\d+/]", em[2].match) !== nothing
                @test em[3].match == "[host=$(gethostname())]"
                @test log_elem[2] == "INFO"
                @test log_elem[3] == "info_test"
            end
        end

        @testset "WARN test" begin
            io = IOBuffer()
            global_logger(QXLogger(io; show_info_source=true))

            @warn "warn_test"; line_num = @__LINE__

            log = split(String(take!(io)), "\n")[1:end-1]
            df = DateFormat("[yyyy/mm/dd-HH:MM:SS.sss]");

            for l in log
                log_elem = split(l, " ")
                em = collect(eachmatch(r"\[(.*?)\]", log_elem[1])) # capture values in []
                @test DateTime(em[1].match, df) !== nothing
                @test match(r"[rank=/\d+/]", em[2].match) !== nothing
                @test em[3].match == "[host=$(gethostname())]"
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
            global_logger(QXLogger(io; show_info_source=true))

            line_num = @__LINE__; @error "error_test"

            log = split(String(take!(io)), "\n")[1:end-1]
            df = DateFormat("[yyyy/mm/dd-HH:MM:SS.sss]");

            for l in log
                log_elem = split(l, " ")
                em = collect(eachmatch(r"\[(.*?)\]", log_elem[1])) # capture values in []
                @test DateTime(em[1].match, df) !== nothing
                @test match(r"[rank=/\d+/]", em[2].match) !== nothing
                @test em[3].match == "[host=$(gethostname())]"
                @test log_elem[2] == "ERROR"
                @test log_elem[3] == "error_test"
                @test log_elem[4] == "-@->"
                file_line = splitext(log_elem[5])
                @test file_line[1] == splitext(@__FILE__)[1]
                @test split(file_line[2], ":")[2] == string(line_num)
            end
        end
    end

    @testset "QXLoggerMPIPerRank" begin

        @testset "WARN test" begin

            mktempdir() do path
                # Fail to create logger if  MPI not initialised
                if !MPI.Initialized()
                    @test_throws """MPI is required for this logger. Pleasure ensure MPI is initialised. Use `QXLogger` for non-distributed logging""" QXLoggerMPIPerRank()
                    MPI.Init()
                end

                global_logger(QXLoggerMPIPerRank(; show_info_source=true, path=path))

                line_num = @__LINE__; @warn "warn_test"

                df = DateFormat("[yyyy/mm/dd-HH:MM:SS.sss]");
                @test isdir(joinpath(path, "QXContexts_io_" * string(global_logger().session_id)))

                log = readlines(joinpath(path, "QXContexts_io_" * string(global_logger().session_id), "rank_0.log"))

                for l in log
                    log_elem = split(l, " ")
                    em = collect(eachmatch(r"\[(.*?)\]", log_elem[1])) # capture values in []
                    @test DateTime(em[1].match, df) !== nothing
                    @test match(r"[rank=/\d+/]", em[2].match) !== nothing
                    @test em[3].match == "[host=$(gethostname())]"
                    @test log_elem[2] == "WARN"
                    @test log_elem[3] == "warn_test"
                    @test log_elem[4] == "-@->"
                    file_line = splitext(log_elem[5])
                    @test file_line[1] == splitext(@__FILE__)[1]
                    @test split(file_line[2], ":")[2] == string(line_num)
                end
            end
        end

    end

end

end