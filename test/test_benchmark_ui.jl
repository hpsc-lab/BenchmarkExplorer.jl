using Test
using BenchmarkExplorer
using JSON
using Dates
using Statistics

@testset "BenchmarkUI" begin
    safe_mktempdir() do test_dir
        mock_data = Dict(
        "version" => "2.0",
        "cached_at" => string(now()),
        "groups" => Dict(
            "test_group" => Dict(
                "bench1" => Dict(
                    "1" => Dict(
                        "mean_time_ns" => 1000.0,
                        "median_time_ns" => 950.0,
                        "min_time_ns" => 900.0,
                        "max_time_ns" => 1100.0,
                        "std_time_ns" => 50.0,
                        "memory_bytes" => 1024,
                        "allocs" => 10,
                        "samples" => 100,
                        "timestamp" => "2024-01-01T10:00:00",
                        "julia_version" => "1.11.0",
                        "commit_hash" => "abc1234567890def"
                    ),
                    "2" => Dict(
                        "mean_time_ns" => 1100.0,
                        "median_time_ns" => 1050.0,
                        "min_time_ns" => 1000.0,
                        "max_time_ns" => 1200.0,
                        "std_time_ns" => 55.0,
                        "memory_bytes" => 2048,
                        "allocs" => 15,
                        "samples" => 100,
                        "timestamp" => "2024-01-02T10:00:00",
                        "julia_version" => "1.11.0",
                        "commit_hash" => "def9876543210abc"
                    ),
                    "3" => Dict(
                        "mean_time_ns" => 950.0,
                        "median_time_ns" => 900.0,
                        "min_time_ns" => 850.0,
                        "max_time_ns" => 1050.0,
                        "std_time_ns" => 45.0,
                        "memory_bytes" => 1536,
                        "allocs" => 12,
                        "samples" => 100,
                        "timestamp" => "2024-01-03T10:00:00",
                        "julia_version" => "1.11.0",
                        "commit_hash" => "fedcba0987654321"
                    )
                ),
                "bench2/subbench" => Dict(
                    "1" => Dict(
                        "mean_time_ns" => 5000.0,
                        "median_time_ns" => 4900.0,
                        "min_time_ns" => 4800.0,
                        "max_time_ns" => 5200.0,
                        "std_time_ns" => 100.0,
                        "memory_bytes" => 4096,
                        "allocs" => 20,
                        "samples" => 50,
                        "timestamp" => "2024-01-01T10:00:00",
                        "julia_version" => "1.11.0",
                        "commit_hash" => "abc1234567890def"
                    )
                )
            )
        )
    )

    latest_path = joinpath(test_dir, "latest_100.json")
    open(latest_path, "w") do f
        JSON.print(f, mock_data, 2)
    end

    index_data = Dict(
        "version" => "2.0",
        "groups" => Dict(
            "test_group" => Dict(
                "total_runs" => 3,
                "latest_run" => 3
            )
        ),
        "last_updated" => string(now())
    )

    index_path = joinpath(test_dir, "index.json")
    open(index_path, "w") do f
        JSON.print(f, index_data, 2)
    end

    @testset "load_dashboard_data" begin

        data = load_dashboard_data(test_dir)

        @test data isa DashboardData
        @test length(data.groups) == 1
        @test "test_group" in data.groups
        @test haskey(data.histories, "test_group")
        @test data.stats.total_benchmarks == 2
        @test data.stats.total_runs == 3
    end

    @testset "prepare_plot_data" begin

        data = load_dashboard_data(test_dir)
        history = data.histories["test_group"]


        plot_data = prepare_plot_data(history, "bench1"; metric=:mean)
        @test length(plot_data.y) == 3
        @test plot_data.y[1] ≈ 1000.0 / 1e6
        @test plot_data.y[2] ≈ 1100.0 / 1e6
        @test plot_data.y[3] ≈ 950.0 / 1e6
        @test length(plot_data.commit_hashes) == 3
        @test plot_data.commit_hashes[1] == "abc1234567890def"
        @test plot_data.commit_hashes[2] == "def9876543210abc"
        @test plot_data.commit_hashes[3] == "fedcba0987654321"
        @test length(plot_data.julia_versions) == 3
        @test length(plot_data.mean) == 3
        @test length(plot_data.median) == 3
        @test length(plot_data.min) == 3
        @test length(plot_data.max) == 3
        @test length(plot_data.memory) == 3
        @test length(plot_data.allocs) == 3


        plot_data_min = prepare_plot_data(history, "bench1"; metric=:min)
        @test plot_data_min.y[1] ≈ 900.0 / 1e6


        plot_data_median = prepare_plot_data(history, "bench1"; metric=:median)
        @test plot_data_median.y[1] ≈ 950.0 / 1e6


        plot_data_pct = prepare_plot_data(history, "bench1"; metric=:mean, as_percentage=true)
        @test plot_data_pct.y[1] ≈ 0.0  # baseline
        @test plot_data_pct.y[2] ≈ 10.0  # 10% increase
        @test plot_data_pct.y[3] ≈ -5.0  # 5% decrease


        plot_data_limited = prepare_plot_data(history, "bench1"; metric=:mean, max_runs=2)
        @test length(plot_data_limited.y) == 2
        @test plot_data_limited.y[1] ≈ 1100.0 / 1e6  # Should be runs 2 and 3


        plot_data_empty = prepare_plot_data(history, "nonexistent")
        @test isempty(plot_data_empty.y)
        @test isempty(plot_data_empty.commit_hashes)
    end

    @testset "format_time_short" begin

        @test format_time_short(500.0) == "500 ns"
        @test format_time_short(1500.0) == "1.5 μs"
        @test format_time_short(1.5e6) == "1.5 ms"
        @test format_time_short(2.5e9) == "2.50 s"
    end

    @testset "format_memory" begin

        @test format_memory(512) == "512 B"
        @test format_memory(2048) == "2.0 KB"
        @test format_memory(2 * 1024^2) == "2.0 MB"
        @test format_memory(3 * 1024^3) == "3.00 GB"
    end

    @testset "format_commit_hash" begin

        @test format_commit_hash("abc1234567890def") == "abc1234"
        @test format_commit_hash("abc1234567890def"; length=10) == "abc1234567"
        @test format_commit_hash("short") == "short"
        @test format_commit_hash("") == "unknown"
        @test format_commit_hash("unknown") == "unknown"
    end

    @testset "get_benchmark_groups" begin

        data = load_dashboard_data(test_dir)
        history = data.histories["test_group"]

        groups = get_benchmark_groups(history)
        @test haskey(groups, "bench1")
        @test haskey(groups, "bench2")
        @test "bench1" in groups["bench1"]
        @test "bench2/subbench" in groups["bench2"]
    end

    @testset "get_benchmark_summary" begin

        data = load_dashboard_data(test_dir)
        history = data.histories["test_group"]

        summary = get_benchmark_summary(history, "bench1", 1)
        @test !isnothing(summary)
        @test summary.mean == 1000.0
        @test summary.median == 950.0
        @test summary.min == 900.0
        @test summary.max == 1100.0
        @test summary.memory == 1024
        @test summary.allocs == 10
        @test summary.timestamp == "2024-01-01T10:00:00"
        @test summary.julia_version == "1.11.0"


        summary_none = get_benchmark_summary(history, "bench1", 999)
        @test isnothing(summary_none)


        summary_none2 = get_benchmark_summary(history, "nonexistent", 1)
        @test isnothing(summary_none2)
    end

    @testset "calculate_stats" begin

        data = load_dashboard_data(test_dir)

        @test data.stats.total_benchmarks == 2
        @test data.stats.total_runs == 3
        @test !isnothing(data.stats.last_run)
        @test data.stats.fastest[2] < data.stats.slowest[2]
    end
    end
end
