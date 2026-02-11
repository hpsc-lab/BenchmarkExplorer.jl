using Statistics

@testset "Static Page Generation" begin

    @testset "aggregate_by_commit" begin
        function aggregate_by_commit(plot_data_mean, plot_data_min, plot_data_median)
            commit_order = String[]
            commit_indices = Dict{String, Vector{Int}}()
            for (i, hash) in enumerate(plot_data_mean.commit_hashes)
                if !haskey(commit_indices, hash)
                    commit_indices[hash] = Int[]
                    push!(commit_order, hash)
                end
                push!(commit_indices[hash], i)
            end
            agg_mean_y = Float64[]; agg_mean_err = Float64[]
            agg_min_y = Float64[]; agg_median_y = Float64[]
            agg_timestamps = String[]; agg_commit_hashes = String[]
            agg_julia_versions = String[]
            agg_memory = Int[]; agg_allocs = Int[]; agg_n_samples = Int[]
            agg_mean_vals = Float64[]; agg_median_vals = Float64[]; agg_min_vals = Float64[]
            for hash in commit_order
                idx = commit_indices[hash]
                n = length(idx)
                means = [plot_data_mean.mean[i] for i in idx]
                medians = [plot_data_median.median[i] for i in idx]
                mins = [plot_data_min.min[i] for i in idx]
                push!(agg_mean_y, mean(means))
                push!(agg_mean_err, n > 1 ? std(means) : 0.0)
                push!(agg_min_y, mean(mins))
                push!(agg_median_y, mean(medians))
                push!(agg_timestamps, plot_data_mean.timestamps[idx[end]])
                push!(agg_commit_hashes, hash)
                push!(agg_julia_versions, plot_data_mean.julia_versions[idx[end]])
                push!(agg_memory, plot_data_mean.memory[idx[end]])
                push!(agg_allocs, plot_data_mean.allocs[idx[end]])
                push!(agg_n_samples, n)
                push!(agg_mean_vals, mean(means))
                push!(agg_median_vals, mean(medians))
                push!(agg_min_vals, mean(mins))
            end
            return (
                mean_y = agg_mean_y, mean_err = agg_mean_err,
                min_y = agg_min_y, median_y = agg_median_y,
                timestamps = agg_timestamps, commit_hashes = agg_commit_hashes,
                julia_versions = agg_julia_versions, memory = agg_memory,
                allocs = agg_allocs, n_samples = agg_n_samples,
                mean_vals = agg_mean_vals, median_vals = agg_median_vals,
                min_vals = agg_min_vals
            )
        end

        @testset "single run per commit" begin
            plot_mean = (
                mean = [1.0, 2.0, 3.0],
                commit_hashes = ["aaa", "bbb", "ccc"],
                timestamps = ["2026-01-01T10:00:00", "2026-01-02T10:00:00", "2026-01-03T10:00:00"],
                julia_versions = ["1.11", "1.11", "1.11"],
                memory = [1024, 2048, 4096],
                allocs = [10, 20, 30],
                y = [1.0, 2.0, 3.0]
            )
            plot_min = (min = [0.9, 1.8, 2.7], y = [0.9, 1.8, 2.7])
            plot_median = (median = [1.0, 2.0, 3.0], y = [1.0, 2.0, 3.0])

            agg = aggregate_by_commit(plot_mean, plot_min, plot_median)

            @test length(agg.mean_y) == 3
            @test agg.mean_y == [1.0, 2.0, 3.0]
            @test all(agg.mean_err .== 0.0)
            @test agg.n_samples == [1, 1, 1]
            @test agg.commit_hashes == ["aaa", "bbb", "ccc"]
        end

        @testset "multiple runs same commit" begin
            plot_mean = (
                mean = [1.0, 1.2, 1.1, 2.0],
                commit_hashes = ["aaa", "aaa", "aaa", "bbb"],
                timestamps = ["2026-01-01T10:00:00", "2026-01-01T11:00:00", "2026-01-01T12:00:00", "2026-01-02T10:00:00"],
                julia_versions = ["1.11", "1.11", "1.11", "1.11"],
                memory = [1024, 1024, 1024, 2048],
                allocs = [10, 10, 10, 20],
                y = [1.0, 1.2, 1.1, 2.0]
            )
            plot_min = (min = [0.9, 1.1, 1.0, 1.8], y = [0.9, 1.1, 1.0, 1.8])
            plot_median = (median = [1.0, 1.2, 1.1, 2.0], y = [1.0, 1.2, 1.1, 2.0])

            agg = aggregate_by_commit(plot_mean, plot_min, plot_median)

            @test length(agg.mean_y) == 2
            @test agg.n_samples == [3, 1]
            @test agg.commit_hashes == ["aaa", "bbb"]
            @test agg.mean_y[1] ≈ (1.0 + 1.2 + 1.1) / 3
            @test agg.mean_err[1] > 0
            @test agg.mean_y[2] ≈ 2.0
            @test agg.mean_err[2] == 0.0
            @test agg.min_y[1] ≈ (0.9 + 1.1 + 1.0) / 3
            @test agg.median_y[1] ≈ (1.0 + 1.2 + 1.1) / 3
        end

        @testset "preserves commit order" begin
            plot_mean = (
                mean = [1.0, 2.0, 3.0],
                commit_hashes = ["ccc", "aaa", "bbb"],
                timestamps = ["2026-01-03T10:00:00", "2026-01-01T10:00:00", "2026-01-02T10:00:00"],
                julia_versions = ["1.11", "1.11", "1.11"],
                memory = [4096, 1024, 2048],
                allocs = [30, 10, 20],
                y = [1.0, 2.0, 3.0]
            )
            plot_min = (min = [0.9, 1.8, 2.7], y = [0.9, 1.8, 2.7])
            plot_median = (median = [1.0, 2.0, 3.0], y = [1.0, 2.0, 3.0])

            agg = aggregate_by_commit(plot_mean, plot_min, plot_median)
            @test agg.commit_hashes == ["ccc", "aaa", "bbb"]
        end

        @testset "uses last timestamp per commit" begin
            plot_mean = (
                mean = [1.0, 1.2],
                commit_hashes = ["aaa", "aaa"],
                timestamps = ["2026-01-01T10:00:00", "2026-01-01T14:00:00"],
                julia_versions = ["1.11", "1.11"],
                memory = [1024, 2048],
                allocs = [10, 20],
                y = [1.0, 1.2]
            )
            plot_min = (min = [0.9, 1.1], y = [0.9, 1.1])
            plot_median = (median = [1.0, 1.2], y = [1.0, 1.2])

            agg = aggregate_by_commit(plot_mean, plot_min, plot_median)
            @test agg.timestamps[1] == "2026-01-01T14:00:00"
            @test agg.memory[1] == 2048
        end
    end

    @testset "generate_index_page" begin
        index_script = joinpath(@__DIR__, "../ci/generate_index_page.jl")
        idx_mod = Module(:IndexPageTestModule)
        Base.include(idx_mod, index_script)

        @testset "produces valid HTML with groups" begin
            safe_mktempdir() do temp_dir
                index = Dict(
                    "version" => "2.0",
                    "groups" => Dict(
                        "trixi" => Dict("total_runs" => 5, "last_run_date" => "2026-01-05"),
                        "enzyme" => Dict("total_runs" => 3, "last_run_date" => "2026-01-03")
                    ),
                    "last_updated" => "2026-01-05T10:00:00"
                )

                open(joinpath(temp_dir, "index.json"), "w") do f
                    JSON.print(f, index, 2)
                end

                latest = Dict(
                    "groups" => Dict(
                        "trixi" => Dict("b1" => Dict(), "b2" => Dict()),
                        "enzyme" => Dict("b1" => Dict())
                    )
                )

                open(joinpath(temp_dir, "latest_100.json"), "w") do f
                    JSON.print(f, latest, 2)
                end

                output_html = joinpath(temp_dir, "index.html")
                Base.invokelatest(idx_mod.generate_index_page,
                    temp_dir, output_html,
                    "https://github.com/test/repo", "abc1234")

                @test isfile(output_html)
                html = read(output_html, String)
                @test occursin("<!DOCTYPE html>", html)
                @test occursin("trixi", html)
                @test occursin("enzyme", html)
                @test occursin("trixi.html", html)
                @test occursin("enzyme.html", html)
            end
        end

        @testset "handles empty groups" begin
            safe_mktempdir() do temp_dir
                index = Dict("version" => "2.0", "groups" => Dict())
                open(joinpath(temp_dir, "index.json"), "w") do f
                    JSON.print(f, index, 2)
                end

                latest = Dict("groups" => Dict())
                open(joinpath(temp_dir, "latest_100.json"), "w") do f
                    JSON.print(f, latest, 2)
                end

                output_html = joinpath(temp_dir, "index.html")
                Base.invokelatest(idx_mod.generate_index_page,
                    temp_dir, output_html,
                    "https://github.com/test/repo", "abc1234")

                @test isfile(output_html)
                html = read(output_html, String)
                @test occursin("No benchmark data available yet", html)
            end
        end
    end
end
