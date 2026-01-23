@testset "Error Handling" begin
    @testset "empty benchmark suite" begin
        safe_mktempdir() do temp_dir
            empty_suite = BenchmarkGroup()
            @test_throws ErrorException save_benchmark_results(
                empty_suite, "test_group"; data_dir=temp_dir
            )
        end
    end

    @testset "load_history missing cache" begin
        safe_mktempdir() do temp_dir
            @test_throws ErrorException load_history(temp_dir)
        end
    end

    @testset "load_history missing group" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)
            save_benchmark_results(results, "existing_group"; data_dir=temp_dir)

            @test_throws ErrorException load_history(temp_dir; group="nonexistent")
        end
    end

    @testset "generate_all_runs_index missing index" begin
        safe_mktempdir() do temp_dir
            @test_throws ErrorException generate_all_runs_index(temp_dir)
        end
    end

    @testset "update_index missing directory" begin
        safe_mktempdir() do temp_dir
            @test_throws ErrorException BenchmarkExplorer.HistoryManager.update_index(temp_dir)
        end
    end

    @testset "extract_timeseries missing benchmark" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)
            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            history = load_history(temp_dir; group="test_group")
            @test_throws ErrorException extract_timeseries_with_timestamps(
                history, "nonexistent", "nonexistent"
            )
        end
    end

    @testset "corrupted index.json recovery" begin
        safe_mktempdir() do temp_dir
            index_path = joinpath(temp_dir, "index.json")
            mkpath(dirname(index_path))
            open(index_path, "w") do f
                write(f, "not valid json {{{")
            end

            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            index = JSON.parsefile(index_path)
            @test haskey(index, "groups")
            @test haskey(index["groups"], "test_group")
        end
    end

    @testset "corrupted latest_100.json recovery" begin
        safe_mktempdir() do temp_dir
            cache_path = joinpath(temp_dir, "latest_100.json")
            mkpath(dirname(cache_path))
            open(cache_path, "w") do f
                write(f, "invalid json")
            end

            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(results, "test_group"; data_dir=temp_dir)

            cache = JSON.parsefile(cache_path)
            @test haskey(cache, "groups")
            @test haskey(cache["groups"], "test_group")
        end
    end

    @testset "load_by_hash nonexistent directory" begin
        safe_mktempdir() do temp_dir
            result = load_by_hash("abc123"; data_dir=temp_dir)
            @test isnothing(result)
        end
    end

    @testset "load_by_hash without group filter" begin
        safe_mktempdir() do temp_dir
            suite = BenchmarkGroup()
            suite["test"] = @benchmarkable sin(1.0)
            results = run(suite)

            save_benchmark_results(
                results, "group1"; data_dir=temp_dir, commit_hash="abc123"
            )
            save_benchmark_results(
                results, "group2"; data_dir=temp_dir, commit_hash="abc123"
            )

            all_groups = load_by_hash("abc123"; data_dir=temp_dir)
            @test !isnothing(all_groups)
            @test haskey(all_groups, "group1")
            @test haskey(all_groups, "group2")
        end
    end
end
