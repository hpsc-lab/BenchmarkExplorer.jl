@testset "Extended Fields" begin
    @testset "new benchmark fields (percentiles, iqr, cv, gc)" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            run_file = joinpath(temp_dir, "by_group", "test_group", "run_1.json")
            data = JSON.parsefile(run_file)
            bench = data["benchmarks"]["test"]

            @test haskey(bench, "p25_time_ns")
            @test haskey(bench, "p75_time_ns")
            @test haskey(bench, "p95_time_ns")
            @test haskey(bench, "p99_time_ns")
            @test haskey(bench, "iqr_time_ns")
            @test haskey(bench, "cv")
            @test haskey(bench, "gc_time_ns")

            @test bench["p25_time_ns"] >= bench["min_time_ns"]
            @test bench["p75_time_ns"] >= bench["p25_time_ns"]
            @test bench["p95_time_ns"] >= bench["p75_time_ns"]
            @test bench["p99_time_ns"] >= bench["p95_time_ns"]
            @test bench["max_time_ns"] >= bench["p99_time_ns"]

            @test bench["iqr_time_ns"] == bench["p75_time_ns"] - bench["p25_time_ns"]
            @test bench["iqr_time_ns"] >= 0

            @test bench["cv"] >= 0
            if bench["mean_time_ns"] > 0 && bench["std_time_ns"] > 0
                expected_cv = bench["std_time_ns"] / bench["mean_time_ns"]
                @test bench["cv"] ≈ expected_cv
            end

            @test bench["gc_time_ns"] >= 0
        end
    end

    @testset "system info in metadata" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            run_file = joinpath(temp_dir, "by_group", "test_group", "run_1.json")
            data = JSON.parsefile(run_file)
            meta = data["metadata"]

            @test haskey(meta, "system")
            system = meta["system"]

            @test haskey(system, "os")
            @test haskey(system, "arch")
            @test haskey(system, "cpu_threads")
            @test haskey(system, "word_size")
            @test haskey(system, "julia_threads")

            @test system["os"] == string(Sys.KERNEL)
            @test system["arch"] == string(Sys.ARCH)
            @test system["cpu_threads"] == Sys.CPU_THREADS
            @test system["word_size"] == Sys.WORD_SIZE
            @test system["julia_threads"] == Threads.nthreads()
        end
    end

    @testset "git metadata fields" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            run_file = joinpath(temp_dir, "by_group", "test_group", "run_1.json")
            data = JSON.parsefile(run_file)
            meta = data["metadata"]

            @test haskey(meta, "git_branch")
            @test haskey(meta, "git_dirty")
            @test haskey(meta, "hostname")

            @test meta["git_branch"] isa String
            @test meta["git_dirty"] isa Bool
            @test meta["hostname"] isa String
            @test !isempty(meta["hostname"])
        end
    end

    @testset "git helper functions" begin
        HM = BenchmarkExplorer.HistoryManager

        branch = HM.get_git_branch()
        @test branch isa AbstractString

        dirty = HM.is_git_dirty()
        @test dirty isa Bool
    end

    @testset "percentile ordering with multiple samples" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["varying"] = @benchmarkable begin
                x = rand()
                sleep(x * 0.0001)
            end
            results = run(suite, samples=20, evals=1)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            run_file = joinpath(temp_dir, "by_group", "test_group", "run_1.json")
            data = JSON.parsefile(run_file)
            bench = data["benchmarks"]["varying"]

            @test bench["min_time_ns"] <= bench["p25_time_ns"]
            @test bench["p25_time_ns"] <= bench["median_time_ns"]
            @test bench["median_time_ns"] <= bench["p75_time_ns"]
            @test bench["p75_time_ns"] <= bench["p95_time_ns"]
            @test bench["p95_time_ns"] <= bench["p99_time_ns"]
            @test bench["p99_time_ns"] <= bench["max_time_ns"]
        end
    end
end
