@testset "Markdown Report" begin
    @testset "basic report generation" begin
        run_data = Dict(
            "metadata" => Dict(
                "run_number" => 1,
                "timestamp" => "2024-01-15T10:30:00",
                "julia_version" => "1.11.0",
                "commit_hash" => "abc1234"
            ),
            "benchmarks" => Dict(
                "math/sin" => Dict("mean_time_ns" => 1000000.0),
                "math/cos" => Dict("mean_time_ns" => 1100000.0)
            )
        )

        report = BenchmarkExplorer.HistoryManager.generate_markdown_report(run_data)

        @test occursin("# Run #1", report)
        @test occursin("2024-01-15", report)
        @test occursin("Julia 1.11.0", report)
        @test occursin("2 benchmarks", report)
        @test occursin("abc1234", report)
    end

    @testset "report with significant changes" begin
        prev_data = Dict(
            "metadata" => Dict(
                "run_number" => 1,
                "timestamp" => "2024-01-14T10:00:00",
                "julia_version" => "1.11.0"
            ),
            "benchmarks" => Dict(
                "test1" => Dict("mean_time_ns" => 1000000.0),
                "test2" => Dict("mean_time_ns" => 2000000.0),
                "test3" => Dict("mean_time_ns" => 3000000.0)
            )
        )

        curr_data = Dict(
            "metadata" => Dict(
                "run_number" => 2,
                "timestamp" => "2024-01-15T10:00:00",
                "julia_version" => "1.11.0"
            ),
            "benchmarks" => Dict(
                "test1" => Dict("mean_time_ns" => 1200000.0),
                "test2" => Dict("mean_time_ns" => 2000000.0),
                "test3" => Dict("mean_time_ns" => 2400000.0)
            )
        )

        report = BenchmarkExplorer.HistoryManager.generate_markdown_report(
            curr_data, prev_data
        )

        @test occursin("Significant Changes", report)
        @test occursin("test1", report)
        @test occursin("test3", report)
        @test occursin("+20.0%", report) || occursin("+20%", report)
        @test occursin("-20.0%", report) || occursin("-20%", report)
    end

    @testset "report without significant changes" begin
        prev_data = Dict(
            "metadata" => Dict(
                "run_number" => 1,
                "timestamp" => "2024-01-14T10:00:00",
                "julia_version" => "1.11.0"
            ),
            "benchmarks" => Dict(
                "test1" => Dict("mean_time_ns" => 1000000.0)
            )
        )

        curr_data = Dict(
            "metadata" => Dict(
                "run_number" => 2,
                "timestamp" => "2024-01-15T10:00:00",
                "julia_version" => "1.11.0"
            ),
            "benchmarks" => Dict(
                "test1" => Dict("mean_time_ns" => 1010000.0)
            )
        )

        report = BenchmarkExplorer.HistoryManager.generate_markdown_report(
            curr_data, prev_data
        )

        @test !occursin("Significant Changes", report)
    end

    @testset "report without commit hash" begin
        run_data = Dict(
            "metadata" => Dict(
                "run_number" => 1,
                "timestamp" => "2024-01-15T10:30:00",
                "julia_version" => "1.11.0"
            ),
            "benchmarks" => Dict(
                "test" => Dict("mean_time_ns" => 1000000.0)
            )
        )

        report = BenchmarkExplorer.HistoryManager.generate_markdown_report(run_data)

        @test occursin("# Run #1", report)
        @test !occursin("unknown", lowercase(report))
    end

    @testset "report file creation on save" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            today = Dates.format(now(), "yyyy-mm")
            day = Dates.format(now(), "dd")
            report_path = joinpath(temp_dir, "by_date", today, day, "report.md")

            @test isfile(report_path)
            content = read(report_path, String)
            @test occursin("# Run #1", content)
        end
    end

    @testset "report appending for multiple runs same day" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "group1"; data_dir=temp_dir)
            save_benchmark_results(results, "group2"; data_dir=temp_dir)

            today = Dates.format(now(), "yyyy-mm")
            day = Dates.format(now(), "dd")
            report_path = joinpath(temp_dir, "by_date", today, day, "report.md")

            content = read(report_path, String)
            @test count("# Run #1", content) == 2
            @test occursin("---", content)
        end
    end
end
