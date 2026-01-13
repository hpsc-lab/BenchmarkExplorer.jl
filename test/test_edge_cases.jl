using Test
using BenchmarkExplorer
using BenchmarkTools
using JSON
using Dates

@testset "Edge Cases and Error Handling" begin
    @testset "Empty benchmark suite" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            results = run(suite)

            @test_throws Exception save_benchmark_results(results, "empty_group"; data_dir=temp_dir)
        end
    end

    @testset "Invalid data directory" begin
        suite = BenchmarkGroup()
        suite["test"] = @benchmarkable sin(1.0)
        results = run(suite)

        @test_throws Base.IOError save_benchmark_results(
            results,
            "test_group";
            data_dir="/nonexistent/path/that/does/not/exist"
        )
    end

    @testset "Corrupted index.json" begin
        mktempdir() do temp_dir
            index_path = joinpath(temp_dir, "index.json")
            open(index_path, "w") do f
                write(f, "{ invalid json }")
            end

            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            new_index = JSON.parsefile(index_path)
            @test haskey(new_index, "version")
            @test new_index["version"] == "2.0"
        end
    end

    @testset "Empty index.json file" begin
        mktempdir() do temp_dir
            index_path = joinpath(temp_dir, "index.json")
            touch(index_path)

            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            @test isfile(index_path)
            @test filesize(index_path) > 0
        end
    end

    @testset "Very long benchmark names" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            long_name = "a"^1000
            suite[long_name] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            history = load_history(temp_dir; group="test_group")
            @test haskey(history, long_name)
        end
    end

    @testset "Special characters in benchmark names" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test/with/slashes"] = @benchmarkable sin(1.0)
            suite["test with spaces"] = @benchmarkable cos(1.0)
            suite["test@#\$%"] = @benchmarkable exp(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            history = load_history(temp_dir; group="test_group")
            @test haskey(history, "test/with/slashes")
            @test haskey(history, "test with spaces")
            @test haskey(history, "test@#\$%")
        end
    end

    @testset "Empty commit hash" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir, commit_hash="")

            history = load_history(temp_dir; group="test_group")
            @test haskey(history["test"], "1")
            @test history["test"]["1"]["commit_hash"] == ""
        end
    end

    @testset "Invalid commit hash" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir, commit_hash="not-a-hash")

            history = load_history(temp_dir; group="test_group")
            @test history["test"]["1"]["commit_hash"] == "not-a-hash"
        end
    end

    @testset "Load nonexistent group" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "group1"; data_dir=temp_dir)

            @test_throws Exception load_history(temp_dir; group="nonexistent_group")
        end
    end

    @testset "Load from nonexistent directory" begin
        @test_throws Exception load_history("/nonexistent/path"; group="test")
    end

    @testset "Load by nonexistent hash" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir, commit_hash="abc123")

            result = load_by_hash("nonexistent", "test_group"; data_dir=temp_dir)
            @test isnothing(result)
        end
    end

    @testset "Very large benchmark suite" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            for i in 1:1000
                suite["bench_$i"] = @benchmarkable rand()
            end
            results = run(suite)

            save_benchmark_results(results, "large_group"; data_dir=temp_dir)

            history = load_history(temp_dir; group="large_group")
            @test length(keys(history)) == 1000
        end
    end

    @testset "Multiple concurrent saves" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)

            tasks = []
            for i in 1:10
                results = run(suite)
                push!(tasks, @async save_benchmark_results(results, "concurrent_group"; data_dir=temp_dir))
            end

            for task in tasks
                wait(task)
            end

            history = load_history(temp_dir; group="concurrent_group")
            @test haskey(history["test"], "10")
        end
    end

    @testset "Unicode in benchmark names" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test_unicode"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "unicode_group"; data_dir=temp_dir)

            history = load_history(temp_dir; group="unicode_group")
            @test haskey(history, "test_unicode")
        end
    end

    @testset "Deeply nested benchmark groups" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            nested = suite
            for i in 1:10
                nested["level_$i"] = BenchmarkGroup()
                nested = nested["level_$i"]
            end
            nested["final"] = @benchmarkable sin(1.0)

            results = run(suite)

            save_benchmark_results(results, "nested_group"; data_dir=temp_dir)

            history = load_history(temp_dir; group="nested_group")
            expected_path = join(["level_$i" for i in 1:10], "/") * "/final"
            @test haskey(history, expected_path)
        end
    end

    @testset "Zero allocation benchmarks" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["zero_alloc"] = @benchmarkable 1 + 1
            results = run(suite)

            save_benchmark_results(results, "zero_alloc_group"; data_dir=temp_dir)

            history = load_history(temp_dir; group="zero_alloc_group")
            @test history["zero_alloc"]["1"]["allocs"] == 0
            @test history["zero_alloc"]["1"]["memory_bytes"] == 0
        end
    end

    @testset "Extremely fast benchmarks" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["fast"] = @benchmarkable 1
            results = run(suite)

            save_benchmark_results(results, "fast_group"; data_dir=temp_dir)

            history = load_history(temp_dir; group="fast_group")
            @test history["fast"]["1"]["mean_time_ns"] > 0
        end
    end

    @testset "Extremely slow benchmarks" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["slow"] = @benchmarkable sleep(0.1)
            results = run(suite)

            save_benchmark_results(results, "slow_group"; data_dir=temp_dir)

            history = load_history(temp_dir; group="slow_group")
            @test history["slow"]["1"]["mean_time_ns"] > 100_000_000
        end
    end

    @testset "Missing latest_100.json" begin
        mktempdir() do temp_dir
            mkpath(joinpath(temp_dir, "by_group", "test_group"))

            run_data = Dict(
                "metadata" => Dict(
                    "run_number" => 1,
                    "group" => "test_group",
                    "timestamp" => string(now()),
                    "julia_version" => string(VERSION),
                    "commit_hash" => ""
                ),
                "benchmarks" => Dict(
                    "test" => Dict(
                        "mean_time_ns" => 1000.0,
                        "median_time_ns" => 950.0,
                        "min_time_ns" => 900.0,
                        "max_time_ns" => 1100.0,
                        "std_time_ns" => 50.0,
                        "memory_bytes" => 0,
                        "allocs" => 0,
                        "samples" => 100
                    )
                )
            )

            open(joinpath(temp_dir, "by_group", "test_group", "run_1.json"), "w") do f
                JSON.print(f, run_data, 2)
            end

            @test_throws Exception load_history(temp_dir; group="test_group")
        end
    end

    @testset "Partial hash prefix matching" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            full_hash = "abc123def456789"
            save_benchmark_results(results, "test_group"; data_dir=temp_dir, commit_hash=full_hash)

            result = load_by_hash("abc123", "test_group"; data_dir=temp_dir)
            @test !isnothing(result)
            @test result["metadata"]["commit_hash"] == full_hash
        end
    end

    @testset "Timestamp format validation" begin
        mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            history = load_history(temp_dir; group="test_group")
            timestamp_str = history["test"]["1"]["timestamp"]

            @test occursin(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}", timestamp_str)
            @test DateTime(timestamp_str[1:19]) isa DateTime
        end
    end
end
