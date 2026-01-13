using Test
using BenchmarkExplorer
using JSON
using Dates
using Statistics

@testset "BenchmarkUI Extended Tests" begin
    include("../src/BenchmarkUI.jl")
    using .BenchmarkUI

    @testset "format_time_short edge cases" begin
        @test format_time_short(0.0) == "0 ns"
        @test format_time_short(0.5) == "0.5 ns"
        @test format_time_short(999.9) == "1000 ns"
        @test format_time_short(1000.0) == "1.0 μs"
        @test format_time_short(1000000.0) == "1.0 ms"
        @test format_time_short(1000000000.0) == "1.00 s"
        @test format_time_short(1e15) == "1000000.00 s"
        @test format_time_short(-100.0) == "-100 ns"
    end

    @testset "format_memory edge cases" begin
        @test format_memory(0) == "0 B"
        @test format_memory(1) == "1 B"
        @test format_memory(1023) == "1023 B"
        @test format_memory(1024) == "1.0 KB"
        @test format_memory(1024^2) == "1.0 MB"
        @test format_memory(1024^3) == "1.00 GB"
        @test format_memory(1024^4) == "1024.00 GB"
        @test format_memory(-100) == "-100 B"
    end

    @testset "format_commit_hash edge cases" begin
        @test format_commit_hash("") == "unknown"
        @test format_commit_hash("unknown") == "unknown"
        @test format_commit_hash("abc") == "abc"
        @test format_commit_hash("abcdefghijklmnop") == "abcdefg"
        @test format_commit_hash("abc123"; length=3) == "abc"
        @test format_commit_hash("abc123"; length=10) == "abc123"
        @test format_commit_hash("a") == "a"
    end

    @testset "prepare_plot_data with empty history" begin
        history = Dict()
        plot_data = prepare_plot_data(history, "nonexistent")

        @test isempty(plot_data.y)
        @test isempty(plot_data.timestamps)
        @test isempty(plot_data.commit_hashes)
        @test isempty(plot_data.julia_versions)
        @test isempty(plot_data.mean)
    end

    @testset "prepare_plot_data with single run" begin
        history = Dict(
            "test" => Dict(
                "1" => Dict(
                    "mean_time_ns" => 1000.0,
                    "median_time_ns" => 950.0,
                    "min_time_ns" => 900.0,
                    "max_time_ns" => 1100.0,
                    "memory_bytes" => 1024,
                    "allocs" => 10,
                    "timestamp" => "2025-01-01T10:00:00",
                    "julia_version" => "1.11.0",
                    "commit_hash" => "abc123"
                )
            )
        )

        plot_data = prepare_plot_data(history, "test"; metric=:mean)

        @test length(plot_data.y) == 1
        @test plot_data.y[1] ≈ 1000.0 / 1e6
        @test length(plot_data.commit_hashes) == 1
        @test plot_data.commit_hashes[1] == "abc123"
    end

    @testset "prepare_plot_data with max_runs limit" begin
        history = Dict(
            "test" => Dict(
                string(i) => Dict(
                    "mean_time_ns" => Float64(i * 1000),
                    "median_time_ns" => Float64(i * 900),
                    "min_time_ns" => Float64(i * 800),
                    "max_time_ns" => Float64(i * 1100),
                    "memory_bytes" => 1024,
                    "allocs" => 10,
                    "timestamp" => "2025-01-01T10:00:00",
                    "julia_version" => "1.11.0",
                    "commit_hash" => "abc$i"
                ) for i in 1:100
            )
        )

        plot_data = prepare_plot_data(history, "test"; metric=:mean, max_runs=10)

        @test length(plot_data.y) == 10
        @test plot_data.y[end] ≈ 100000.0 / 1e6
    end

    @testset "prepare_plot_data percentage mode" begin
        history = Dict(
            "test" => Dict(
                "1" => Dict(
                    "mean_time_ns" => 1000.0,
                    "median_time_ns" => 950.0,
                    "min_time_ns" => 900.0,
                    "max_time_ns" => 1100.0,
                    "memory_bytes" => 1024,
                    "allocs" => 10,
                    "timestamp" => "2025-01-01T10:00:00",
                    "julia_version" => "1.11.0",
                    "commit_hash" => "abc1"
                ),
                "2" => Dict(
                    "mean_time_ns" => 1200.0,
                    "median_time_ns" => 1150.0,
                    "min_time_ns" => 1100.0,
                    "max_time_ns" => 1300.0,
                    "memory_bytes" => 2048,
                    "allocs" => 20,
                    "timestamp" => "2025-01-02T10:00:00",
                    "julia_version" => "1.11.0",
                    "commit_hash" => "abc2"
                )
            )
        )

        plot_data = prepare_plot_data(history, "test"; metric=:mean, as_percentage=true)

        @test plot_data.y[1] ≈ 0.0
        @test plot_data.y[2] ≈ 20.0
    end

    @testset "prepare_plot_data different metrics" begin
        history = Dict(
            "test" => Dict(
                "1" => Dict(
                    "mean_time_ns" => 1000.0,
                    "median_time_ns" => 950.0,
                    "min_time_ns" => 900.0,
                    "max_time_ns" => 1100.0,
                    "memory_bytes" => 1024,
                    "allocs" => 10,
                    "timestamp" => "2025-01-01T10:00:00",
                    "julia_version" => "1.11.0",
                    "commit_hash" => "abc1"
                )
            )
        )

        plot_mean = prepare_plot_data(history, "test"; metric=:mean)
        plot_median = prepare_plot_data(history, "test"; metric=:median)
        plot_min = prepare_plot_data(history, "test"; metric=:min)
        plot_max = prepare_plot_data(history, "test"; metric=:max)

        @test plot_mean.y[1] ≈ 1000.0 / 1e6
        @test plot_median.y[1] ≈ 950.0 / 1e6
        @test plot_min.y[1] ≈ 900.0 / 1e6
        @test plot_max.y[1] ≈ 1100.0 / 1e6
    end

    @testset "get_benchmark_groups empty history" begin
        history = Dict()
        groups = get_benchmark_groups(history)
        @test isempty(groups)
    end

    @testset "get_benchmark_groups flat benchmarks" begin
        history = Dict(
            "bench1" => Dict("1" => Dict()),
            "bench2" => Dict("1" => Dict()),
            "bench3" => Dict("1" => Dict())
        )

        groups = get_benchmark_groups(history)
        @test haskey(groups, "bench1")
        @test haskey(groups, "bench2")
        @test haskey(groups, "bench3")
    end

    @testset "get_benchmark_groups nested benchmarks" begin
        history = Dict(
            "group1/bench1" => Dict("1" => Dict()),
            "group1/bench2" => Dict("1" => Dict()),
            "group2/bench1" => Dict("1" => Dict())
        )

        groups = get_benchmark_groups(history)
        @test haskey(groups, "group1")
        @test haskey(groups, "group2")
        @test "group1/bench1" in groups["group1"]
        @test "group1/bench2" in groups["group1"]
        @test "group2/bench1" in groups["group2"]
    end

    @testset "get_benchmark_groups deeply nested" begin
        history = Dict(
            "a/b/c/d/e" => Dict("1" => Dict())
        )

        groups = get_benchmark_groups(history)
        @test haskey(groups, "a")
        @test "a/b/c/d/e" in groups["a"]
    end

    @testset "get_benchmark_summary missing run" begin
        history = Dict(
            "test" => Dict(
                "1" => Dict(
                    "mean_time_ns" => 1000.0,
                    "median_time_ns" => 950.0,
                    "min_time_ns" => 900.0,
                    "max_time_ns" => 1100.0,
                    "memory_bytes" => 1024,
                    "allocs" => 10,
                    "timestamp" => "2025-01-01T10:00:00",
                    "julia_version" => "1.11.0"
                )
            )
        )

        summary = get_benchmark_summary(history, "test", 999)
        @test isnothing(summary)
    end

    @testset "get_benchmark_summary missing benchmark" begin
        history = Dict(
            "test" => Dict(
                "1" => Dict(
                    "mean_time_ns" => 1000.0,
                    "median_time_ns" => 950.0,
                    "min_time_ns" => 900.0,
                    "max_time_ns" => 1100.0,
                    "memory_bytes" => 1024,
                    "allocs" => 10,
                    "timestamp" => "2025-01-01T10:00:00",
                    "julia_version" => "1.11.0"
                )
            )
        )

        summary = get_benchmark_summary(history, "nonexistent", 1)
        @test isnothing(summary)
    end

    @testset "load_dashboard_data validation" begin
        mktempdir() do temp_dir
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
                                "timestamp" => "2025-01-01T10:00:00",
                                "julia_version" => "1.11.0",
                                "commit_hash" => "abc123"
                            )
                        )
                    )
                )
            )

            latest_path = joinpath(temp_dir, "latest_100.json")
            open(latest_path, "w") do f
                JSON.print(f, mock_data, 2)
            end

            index_data = Dict(
                "version" => "2.0",
                "groups" => Dict(
                    "test_group" => Dict(
                        "total_runs" => 1,
                        "latest_run" => 1
                    )
                ),
                "last_updated" => string(now())
            )

            index_path = joinpath(temp_dir, "index.json")
            open(index_path, "w") do f
                JSON.print(f, index_data, 2)
            end

            data = load_dashboard_data(temp_dir)

            @test data isa DashboardData
            @test "test_group" in data.groups
            @test haskey(data.histories, "test_group")
            @test data.stats.total_benchmarks == 1
            @test data.stats.total_runs == 1
        end
    end

    @testset "calculate_stats empty data" begin
        histories = Dict()

        stats = BenchmarkUI.calculate_stats(histories)

        @test stats.total_benchmarks == 0
        @test stats.total_runs == 0
        @test isnothing(stats.last_run)
    end

    @testset "format_time_ago edge cases" begin
        now_dt = now()

        @test BenchmarkUI.format_time_ago(now_dt) == "just now"
        @test BenchmarkUI.format_time_ago(now_dt - Minute(1)) == "1 minute ago"
        @test BenchmarkUI.format_time_ago(now_dt - Hour(1)) == "1 hour ago"
        @test BenchmarkUI.format_time_ago(now_dt - Day(1)) == "1 day ago"
        @test BenchmarkUI.format_time_ago(now_dt - Day(30)) == "30 days ago"
    end

    @testset "prepare_plot_data with missing fields" begin
        history = Dict(
            "test" => Dict(
                "1" => Dict(
                    "mean_time_ns" => 1000.0,
                    "median_time_ns" => 950.0,
                    "min_time_ns" => 900.0
                )
            )
        )

        plot_data = prepare_plot_data(history, "test"; metric=:mean)

        @test length(plot_data.y) == 1
        @test plot_data.commit_hashes[1] == "unknown"
    end

    @testset "prepare_plot_data with extreme values" begin
        history = Dict(
            "test" => Dict(
                "1" => Dict(
                    "mean_time_ns" => 1e15,
                    "median_time_ns" => 1e15,
                    "min_time_ns" => 1e15,
                    "max_time_ns" => 1e15,
                    "memory_bytes" => typemax(Int64),
                    "allocs" => typemax(Int64),
                    "timestamp" => "2025-01-01T10:00:00",
                    "julia_version" => "1.11.0",
                    "commit_hash" => "abc"
                )
            )
        )

        plot_data = prepare_plot_data(history, "test"; metric=:mean)

        @test isfinite(plot_data.y[1])
        @test plot_data.y[1] > 0
    end
end
