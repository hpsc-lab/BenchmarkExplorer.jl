@testset "HistoryManager" begin
    @testset "flatten_benchmarks" begin
        suite = BenchmarkGroup()
        suite["category1"] = BenchmarkGroup()
        suite["category1"]["test1"] = @benchmarkable sin(1.0)
        suite["category1"]["test2"] = @benchmarkable cos(1.0)
        suite["category2"] = @benchmarkable exp(1.0)

        results = run(suite)
        flattened = BenchmarkExplorer.flatten_benchmarks(results)

        @test haskey(flattened, "category1/test1")
        @test haskey(flattened, "category1/test2")
        @test haskey(flattened, "category2")
        @test length(flattened) == 3

        @test flattened["category1/test1"] isa BenchmarkTools.Trial
        @test flattened["category1/test2"] isa BenchmarkTools.Trial
        @test flattened["category2"] isa BenchmarkTools.Trial
    end

    @testset "save_benchmark_results" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(
                results,
                "test_group";
                data_dir=temp_dir,
                commit_hash="abc123"
            )

            @test isdir(joinpath(temp_dir, "by_date"))
            @test isdir(joinpath(temp_dir, "by_group"))
            @test isdir(joinpath(temp_dir, "by_hash"))
            @test isfile(joinpath(temp_dir, "index.json"))
            @test isfile(joinpath(temp_dir, "latest_100.json"))

            index = JSON.parsefile(joinpath(temp_dir, "index.json"))
            @test haskey(index, "groups")
            @test haskey(index["groups"], "test_group")
            @test index["groups"]["test_group"]["total_runs"] == 1

            latest_100 = JSON.parsefile(joinpath(temp_dir, "latest_100.json"))
            @test haskey(latest_100, "groups")
            @test haskey(latest_100["groups"], "test_group")
            @test haskey(latest_100["groups"]["test_group"], "test")
            @test haskey(latest_100["groups"]["test_group"]["test"], "1")

            hash_file = joinpath(temp_dir, "by_hash", "abc123", "test_group.json")
            @test isfile(hash_file)
            hash_data = JSON.parsefile(hash_file)
            @test hash_data["metadata"]["commit_hash"] == "abc123"
            @test haskey(hash_data, "benchmarks")
            @test haskey(hash_data["benchmarks"], "test")
        end
    end

    @testset "load_history" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)
            save_benchmark_results(results, "test_group"; data_dir=temp_dir)
            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            history = load_history(temp_dir; group="test_group")
            @test haskey(history, "test")
            @test haskey(history["test"], "1")
            @test haskey(history["test"], "2")
            @test haskey(history["test"], "3")

            first_run = history["test"]["1"]
            @test haskey(first_run, "mean_time_ns")
            @test haskey(first_run, "timestamp")
            @test haskey(first_run, "memory_bytes")
            @test haskey(first_run, "allocs")
        end
    end

    @testset "load_by_hash" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(
                results,
                "test_group";
                data_dir=temp_dir,
                commit_hash="abc123def456"
            )

            data = load_by_hash("abc123", "test_group"; data_dir=temp_dir)
            @test !isnothing(data)
            @test data["metadata"]["commit_hash"] == "abc123def456"
            @test haskey(data, "benchmarks")
            @test haskey(data["benchmarks"], "test")

            data_full = load_by_hash("abc123def456", "test_group"; data_dir=temp_dir)
            @test !isnothing(data_full)
            @test data_full["metadata"]["commit_hash"] == "abc123def456"

            data_missing = load_by_hash("nonexistent", "test_group"; data_dir=temp_dir)
            @test isnothing(data_missing)
        end
    end

    @testset "generate_all_runs_index" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "group1"; data_dir=temp_dir)
            save_benchmark_results(results, "group1"; data_dir=temp_dir)
            save_benchmark_results(results, "group2"; data_dir=temp_dir)

            index_path = generate_all_runs_index(temp_dir)
            @test isfile(index_path)

            all_runs = JSON.parsefile(index_path)
            @test haskey(all_runs, "version")
            @test haskey(all_runs, "groups")
            @test haskey(all_runs["groups"], "group1")
            @test haskey(all_runs["groups"], "group2")

            @test all_runs["groups"]["group1"]["total_runs"] == 2
            @test all_runs["groups"]["group2"]["total_runs"] == 1
            @test length(all_runs["groups"]["group1"]["runs"]) == 2
            @test length(all_runs["groups"]["group2"]["runs"]) == 1

            run_info = all_runs["groups"]["group1"]["runs"][1]
            @test haskey(run_info, "run")
            @test haskey(run_info, "date")
            @test haskey(run_info, "url")
        end
    end

    @testset "extract_timeseries_with_timestamps" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            for i in 1:5
                save_benchmark_results(results, "test_group"; data_dir=temp_dir)
                sleep(0.1)
            end

            history = load_history(temp_dir; group="test_group")
            timestamps, means, mins, medians, memory, allocs = extract_timeseries_with_timestamps(history, "test", "test")

            @test length(timestamps) == 5
            @test length(means) == 5
            @test all(t -> t isa DateTime, timestamps)
            @test all(v -> v isa Number, means)
            @test issorted(timestamps)
        end
    end

    @testset "multiple groups and benchmarks" begin
        safe_mktempdir() do temp_dir
            suite1 = BenchmarkGroup()
            suite1["math"] = BenchmarkGroup()
            suite1["math"]["sin"] = @benchmarkable sin(1.0)
            suite1["math"]["cos"] = @benchmarkable cos(1.0)

            suite2 = BenchmarkGroup()
            suite2["exp"] = @benchmarkable exp(1.0)

            results1 = run(suite1)
            results2 = run(suite2)

            save_benchmark_results(results1, "group1"; data_dir=temp_dir, commit_hash="hash1")
            save_benchmark_results(results2, "group2"; data_dir=temp_dir, commit_hash="hash2")

            index = JSON.parsefile(joinpath(temp_dir, "index.json"))
            @test length(index["groups"]) == 2
            @test haskey(index["groups"], "group1")
            @test haskey(index["groups"], "group2")

            latest_100 = JSON.parsefile(joinpath(temp_dir, "latest_100.json"))
            @test haskey(latest_100["groups"]["group1"], "math/sin")
            @test haskey(latest_100["groups"]["group1"], "math/cos")
            @test haskey(latest_100["groups"]["group2"], "exp")

            @test isfile(joinpath(temp_dir, "by_hash", "hash1", "group1.json"))
            @test isfile(joinpath(temp_dir, "by_hash", "hash2", "group2.json"))
        end
    end

    @testset "incremental run numbers" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)
            index1 = JSON.parsefile(joinpath(temp_dir, "index.json"))
            @test index1["groups"]["test_group"]["total_runs"] == 1

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)
            index2 = JSON.parsefile(joinpath(temp_dir, "index.json"))
            @test index2["groups"]["test_group"]["total_runs"] == 2

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)
            index3 = JSON.parsefile(joinpath(temp_dir, "index.json"))
            @test index3["groups"]["test_group"]["total_runs"] == 3

            @test isfile(joinpath(temp_dir, "by_group", "test_group", "run_1.json"))
            @test isfile(joinpath(temp_dir, "by_group", "test_group", "run_2.json"))
            @test isfile(joinpath(temp_dir, "by_group", "test_group", "run_3.json"))
        end
    end

    @testset "commit_hash in latest_100 cache" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(
                results,
                "test_group";
                data_dir=temp_dir,
                commit_hash="abc123def456"
            )

            latest_100 = JSON.parsefile(joinpath(temp_dir, "latest_100.json"))
            @test haskey(latest_100, "groups")
            @test haskey(latest_100["groups"], "test_group")
            @test haskey(latest_100["groups"]["test_group"], "test")
            @test haskey(latest_100["groups"]["test_group"]["test"], "1")

            run_data = latest_100["groups"]["test_group"]["test"]["1"]
            @test haskey(run_data, "commit_hash")
            @test run_data["commit_hash"] == "abc123def456"
            @test haskey(run_data, "julia_version")
            @test haskey(run_data, "timestamp")
            @test haskey(run_data, "mean_time_ns")
            @test haskey(run_data, "median_time_ns")
            @test haskey(run_data, "min_time_ns")
            @test haskey(run_data, "max_time_ns")
            @test haskey(run_data, "memory_bytes")
            @test haskey(run_data, "allocs")


            save_benchmark_results(
                results,
                "test_group";
                data_dir=temp_dir,
                commit_hash="xyz789abc012"
            )

            latest_100_2 = JSON.parsefile(joinpath(temp_dir, "latest_100.json"))
            run_data_2 = latest_100_2["groups"]["test_group"]["test"]["2"]
            @test run_data_2["commit_hash"] == "xyz789abc012"


            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            latest_100_3 = JSON.parsefile(joinpath(temp_dir, "latest_100.json"))
            run_data_3 = latest_100_3["groups"]["test_group"]["test"]["3"]
            @test haskey(run_data_3, "commit_hash")
            @test run_data_3["commit_hash"] == ""
        end
    end
end
