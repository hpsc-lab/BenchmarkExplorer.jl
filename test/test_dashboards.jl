using Test
using BenchmarkExplorer
using BenchmarkTools
using JSON
using Dates

@testset "Dashboard Integration Tests" begin
    safe_mktempdir() do temp_dir
        suite = BenchmarkGroup()
        suite["math"] = BenchmarkGroup()
        suite["math"]["sin"] = @benchmarkable sin(1.0)
        suite["math"]["cos"] = @benchmarkable cos(1.0)
        suite["string"] = BenchmarkGroup()
        suite["string"]["uppercase"] = @benchmarkable uppercase("hello")

        commit_hashes = ["abc1234567890", "def4567890abc", "ghi7890abcdef"]
        for (i, commit_hash) in enumerate(commit_hashes)
            results = run(suite)
            save_benchmark_results(
                results,
                "test_group";
                data_dir=temp_dir,
                commit_hash=commit_hash
            )
            sleep(0.1)
        end

        @testset "Dashboard data loading" begin
            data = load_dashboard_data(temp_dir)

            @test data isa DashboardData
            @test !isempty(data.groups)
            @test "test_group" in data.groups
            @test !isempty(data.histories)
            @test haskey(data.histories, "test_group")

            @test data.stats.total_benchmarks == 3
            @test data.stats.total_runs == 3
            @test !isnothing(data.stats.last_run)
        end

        @testset "Plot data with commit hashes" begin
            data = load_dashboard_data(temp_dir)
            history = data.histories["test_group"]

            plot_data = prepare_plot_data(history, "math/sin"; metric=:mean)

            @test length(plot_data.y) == 3
            @test length(plot_data.commit_hashes) == 3
            @test plot_data.commit_hashes == commit_hashes
            @test all(h -> h in commit_hashes, plot_data.commit_hashes)

            @test length(plot_data.timestamps) == 3
            @test length(plot_data.julia_versions) == 3
            @test length(plot_data.mean) == 3
            @test length(plot_data.median) == 3
            @test length(plot_data.min) == 3
            @test length(plot_data.max) == 3
            @test length(plot_data.memory) == 3
            @test length(plot_data.allocs) == 3

            for hash in plot_data.commit_hashes
                short_hash = format_commit_hash(hash)
                @test length(short_hash) <= 7
                @test startswith(hash, short_hash)
            end
        end

        @testset "Percentage mode" begin
            data = load_dashboard_data(temp_dir)
            history = data.histories["test_group"]

            plot_data_normal = prepare_plot_data(history, "math/sin"; metric=:mean)
            plot_data_pct = prepare_plot_data(history, "math/sin"; metric=:mean, as_percentage=true)

            @test length(plot_data_pct.y) == length(plot_data_normal.y)
            @test plot_data_pct.y[1] ≈ 0.0
            @test any(plot_data_pct.y .!= plot_data_normal.y)
        end

        @testset "Multiple benchmarks" begin
            data = load_dashboard_data(temp_dir)
            history = data.histories["test_group"]

            benchmarks = ["math/sin", "math/cos", "string/uppercase"]
            for bench_path in benchmarks
                plot_data = prepare_plot_data(history, bench_path; metric=:mean)
                @test length(plot_data.y) == 3
                @test length(plot_data.commit_hashes) == 3
            end
        end

        @testset "Benchmark grouping" begin
            data = load_dashboard_data(temp_dir)
            history = data.histories["test_group"]

            groups = get_benchmark_groups(history)
            @test haskey(groups, "math")
            @test haskey(groups, "string")
            @test "math/sin" in groups["math"]
            @test "math/cos" in groups["math"]
            @test "string/uppercase" in groups["string"]
        end

        @testset "All runs index with commit hashes" begin
            index_path = generate_all_runs_index(temp_dir)
            @test isfile(index_path)

            all_runs = JSON.parsefile(index_path)
            @test haskey(all_runs, "groups")
            @test haskey(all_runs["groups"], "test_group")

            runs_list = all_runs["groups"]["test_group"]["runs"]
            @test length(runs_list) == 3

            for (i, run_info) in enumerate(runs_list)
                @test haskey(run_info, "commit_hash")
                @test run_info["commit_hash"] == commit_hashes[i]
            end
        end

        @testset "Data persistence and consistency" begin

            latest_100 = JSON.parsefile(joinpath(temp_dir, "latest_100.json"))
            index = JSON.parsefile(joinpath(temp_dir, "index.json"))

            for (i, commit_hash) in enumerate(commit_hashes)

                bench_data = latest_100["groups"]["test_group"]["math/sin"]["$i"]
                @test bench_data["commit_hash"] == commit_hash


                run_info = index["groups"]["test_group"]["runs"][i]
                @test run_info["commit_hash"] == commit_hash


                hash_file = joinpath(temp_dir, "by_hash", commit_hash, "test_group.json")
                @test isfile(hash_file)
                hash_data = JSON.parsefile(hash_file)
                @test hash_data["metadata"]["commit_hash"] == commit_hash
            end
        end
    end
end
