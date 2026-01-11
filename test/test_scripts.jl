using Test
using JSON
using Dates

@testset "Utility Scripts Tests" begin
    @testset "convert_old_format.jl functionality" begin
        include("../scripts/convert_old_format.jl")

        mktempdir() do temp_dir
            old_data = Dict(
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
                        "timestamp" => "2025-01-02T10:00:00",
                        "julia_version" => "1.11.0",
                        "commit_hash" => "def456"
                    )
                ),
                "bench2" => Dict(
                    "1" => Dict(
                        "mean_time_ns" => 5000.0,
                        "median_time_ns" => 4900.0,
                        "min_time_ns" => 4800.0,
                        "max_time_ns" => 5200.0,
                        "std_time_ns" => 100.0,
                        "memory_bytes" => 4096,
                        "allocs" => 20,
                        "samples" => 50,
                        "timestamp" => "2025-01-01T10:00:00",
                        "julia_version" => "1.11.0",
                        "commit_hash" => "abc123"
                    )
                )
            )

            old_file = joinpath(temp_dir, "old_format.json")
            open(old_file, "w") do f
                JSON.print(f, old_data, 2)
            end

            output_dir = joinpath(temp_dir, "converted")
            convert_old_to_new(old_file, "test_group", output_dir)

            @test isdir(output_dir)
            @test isfile(joinpath(output_dir, "index.json"))
            @test isfile(joinpath(output_dir, "latest_100.json"))

            index = JSON.parsefile(joinpath(output_dir, "index.json"))
            @test haskey(index, "groups")
            @test haskey(index["groups"], "test_group")
            @test index["groups"]["test_group"]["total_runs"] == 2

            latest = JSON.parsefile(joinpath(output_dir, "latest_100.json"))
            @test haskey(latest, "groups")
            @test haskey(latest["groups"], "test_group")
            @test haskey(latest["groups"]["test_group"], "bench1")
            @test haskey(latest["groups"]["test_group"], "bench2")

            @test isfile(joinpath(output_dir, "by_group", "test_group", "run_1.json"))
            @test isfile(joinpath(output_dir, "by_group", "test_group", "run_2.json"))
        end
    end

    @testset "convert_old_format with commit_sha field" begin
        include("../scripts/convert_old_format.jl")

        mktempdir() do temp_dir
            old_data = Dict(
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
                        "commit_sha" => "old_style_hash"
                    )
                )
            )

            old_file = joinpath(temp_dir, "old_format.json")
            open(old_file, "w") do f
                JSON.print(f, old_data, 2)
            end

            output_dir = joinpath(temp_dir, "converted")
            convert_old_to_new(old_file, "test_group", output_dir)

            run_data = JSON.parsefile(joinpath(output_dir, "by_group", "test_group", "run_1.json"))
            @test run_data["metadata"]["commit_hash"] == "old_style_hash"
        end
    end

    @testset "convert_old_format with missing file" begin
        include("../scripts/convert_old_format.jl")

        @test_throws Exception convert_old_to_new("/nonexistent/file.json", "test_group", "output")
    end

    @testset "import_github_benchmark.jl functionality" begin
        include("../scripts/import_github_benchmark.jl")

        mktempdir() do temp_dir
            github_data = Dict(
                "entries" => Dict(
                    "Julia benchmark result" => [
                        Dict(
                            "commit" => Dict(
                                "id" => "abc123",
                                "timestamp" => "2025-01-01T10:00:00Z"
                            ),
                            "benches" => [
                                Dict(
                                    "name" => "bench1",
                                    "value" => 1000.0,
                                    "extra" => "memory=1024\nallocs=10"
                                ),
                                Dict(
                                    "name" => "bench2",
                                    "value" => 2000.0,
                                    "extra" => "memory=2048\nallocs=20"
                                )
                            ]
                        ),
                        Dict(
                            "commit" => Dict(
                                "id" => "def456",
                                "timestamp" => "2025-01-02T10:00:00Z"
                            ),
                            "benches" => [
                                Dict(
                                    "name" => "bench1",
                                    "value" => 1100.0,
                                    "extra" => "memory=1536\nallocs=15"
                                )
                            ]
                        )
                    ]
                )
            )

            input_file = joinpath(temp_dir, "data.js")
            open(input_file, "w") do f
                write(f, "window.BENCHMARK_DATA = ")
                JSON.print(f, github_data)
            end

            output_dir = joinpath(temp_dir, "imported")
            import_github_benchmark(input_file, "test_group", output_dir)

            @test isdir(output_dir)
            @test isfile(joinpath(output_dir, "index.json"))
            @test isfile(joinpath(output_dir, "latest_100.json"))

            index = JSON.parsefile(joinpath(output_dir, "index.json"))
            @test index["groups"]["test_group"]["total_runs"] == 2

            latest = JSON.parsefile(joinpath(output_dir, "latest_100.json"))
            @test haskey(latest["groups"]["test_group"], "bench1")
            @test haskey(latest["groups"]["test_group"], "bench2")
        end
    end

    @testset "import_github_benchmark with missing extra field" begin
        include("../scripts/import_github_benchmark.jl")

        mktempdir() do temp_dir
            github_data = Dict(
                "entries" => Dict(
                    "Julia benchmark result" => [
                        Dict(
                            "commit" => Dict(
                                "id" => "abc123",
                                "timestamp" => "2025-01-01T10:00:00Z"
                            ),
                            "benches" => [
                                Dict(
                                    "name" => "bench1",
                                    "value" => 1000.0
                                )
                            ]
                        )
                    ]
                )
            )

            input_file = joinpath(temp_dir, "data.js")
            open(input_file, "w") do f
                JSON.print(f, github_data)
            end

            output_dir = joinpath(temp_dir, "imported")
            import_github_benchmark(input_file, "test_group", output_dir)

            latest = JSON.parsefile(joinpath(output_dir, "latest_100.json"))
            run_data = latest["groups"]["test_group"]["bench1"]["1"]
            @test run_data["memory_bytes"] == 0
            @test run_data["allocs"] == 0
        end
    end

    @testset "rebuild_cache.jl functionality" begin
        include("../scripts/rebuild_cache.jl")

        mktempdir() do temp_dir
            mkpath(joinpath(temp_dir, "by_group", "test_group"))

            for i in 1:5
                run_data = Dict(
                    "metadata" => Dict(
                        "run_number" => i,
                        "group" => "test_group",
                        "timestamp" => "2025-01-0$(i)T10:00:00",
                        "julia_version" => "1.11.0",
                        "commit_hash" => "hash$i"
                    ),
                    "benchmarks" => Dict(
                        "bench1" => Dict(
                            "mean_time_ns" => Float64(i * 1000),
                            "median_time_ns" => Float64(i * 950),
                            "min_time_ns" => Float64(i * 900),
                            "max_time_ns" => Float64(i * 1100),
                            "std_time_ns" => 50.0,
                            "memory_bytes" => 1024,
                            "allocs" => 10,
                            "samples" => 100
                        )
                    )
                )

                open(joinpath(temp_dir, "by_group", "test_group", "run_$i.json"), "w") do f
                    JSON.print(f, run_data, 2)
                end
            end

            index_data = Dict(
                "version" => "2.0",
                "groups" => Dict(
                    "test_group" => Dict(
                        "runs" => [
                            Dict(
                                "run_number" => i,
                                "timestamp" => "2025-01-0$(i)T10:00:00",
                                "date" => "2025-01-0$i",
                                "julia_version" => "1.11.0",
                                "commit_hash" => "hash$i",
                                "benchmark_count" => 1,
                                "file_path" => "by_group/test_group/run_$i.json"
                            ) for i in 1:5
                        ],
                        "total_runs" => 5,
                        "latest_run" => 5,
                        "first_run_date" => "2025-01-01",
                        "last_run_date" => "2025-01-05"
                    )
                ),
                "last_updated" => string(now())
            )

            open(joinpath(temp_dir, "index.json"), "w") do f
                JSON.print(f, index_data, 2)
            end

            rebuild_latest_cache(temp_dir)

            @test isfile(joinpath(temp_dir, "latest_100.json"))

            latest = JSON.parsefile(joinpath(temp_dir, "latest_100.json"))
            @test haskey(latest, "groups")
            @test haskey(latest["groups"], "test_group")
            @test haskey(latest["groups"]["test_group"], "bench1")

            bench_data = latest["groups"]["test_group"]["bench1"]
            @test length(keys(bench_data)) == 5

            for i in 1:5
                @test haskey(bench_data, string(i))
                @test bench_data[string(i)]["commit_hash"] == "hash$i"
            end
        end
    end

    @testset "rebuild_cache with max_runs limit" begin
        include("../scripts/rebuild_cache.jl")

        mktempdir() do temp_dir
            mkpath(joinpath(temp_dir, "by_group", "test_group"))

            for i in 1:20
                run_data = Dict(
                    "metadata" => Dict(
                        "run_number" => i,
                        "group" => "test_group",
                        "timestamp" => "2025-01-01T10:00:00",
                        "julia_version" => "1.11.0",
                        "commit_hash" => "hash$i"
                    ),
                    "benchmarks" => Dict(
                        "bench1" => Dict(
                            "mean_time_ns" => 1000.0,
                            "median_time_ns" => 950.0,
                            "min_time_ns" => 900.0,
                            "max_time_ns" => 1100.0,
                            "std_time_ns" => 50.0,
                            "memory_bytes" => 1024,
                            "allocs" => 10,
                            "samples" => 100
                        )
                    )
                )

                open(joinpath(temp_dir, "by_group", "test_group", "run_$i.json"), "w") do f
                    JSON.print(f, run_data, 2)
                end
            end

            index_data = Dict(
                "version" => "2.0",
                "groups" => Dict(
                    "test_group" => Dict(
                        "runs" => [
                            Dict(
                                "run_number" => i,
                                "timestamp" => "2025-01-01T10:00:00",
                                "date" => "2025-01-01",
                                "julia_version" => "1.11.0",
                                "commit_hash" => "hash$i",
                                "benchmark_count" => 1,
                                "file_path" => "by_group/test_group/run_$i.json"
                            ) for i in 1:20
                        ],
                        "total_runs" => 20,
                        "latest_run" => 20,
                        "first_run_date" => "2025-01-01",
                        "last_run_date" => "2025-01-01"
                    )
                ),
                "last_updated" => string(now())
            )

            open(joinpath(temp_dir, "index.json"), "w") do f
                JSON.print(f, index_data, 2)
            end

            rebuild_latest_cache(temp_dir; max_runs=10)

            latest = JSON.parsefile(joinpath(temp_dir, "latest_100.json"))
            bench_data = latest["groups"]["test_group"]["bench1"]

            @test length(keys(bench_data)) == 10
            @test haskey(bench_data, "20")
            @test haskey(bench_data, "11")
            @test !haskey(bench_data, "10")
        end
    end

    @testset "parse_extra helper function" begin
        include("../scripts/import_github_benchmark.jl")

        result = parse_extra("memory=1024\nallocs=10\nsamples=100")
        @test result["memory"] == "1024"
        @test result["allocs"] == "10"
        @test result["samples"] == "100"

        result_empty = parse_extra("")
        @test isempty(result_empty)

        result_single = parse_extra("key=value")
        @test result_single["key"] == "value"

        result_no_equals = parse_extra("no equals sign")
        @test isempty(result_no_equals)
    end
end
