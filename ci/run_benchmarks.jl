using Pkg
Pkg.activate(".")
Pkg.instantiate()

using BenchmarkTools
using JSON
using Dates
using Statistics

include("../src/benchmarks_trixi.jl")

history_file = length(ARGS) >= 1 ? ARGS[1] : "data/history_ci.json"
group_name = length(ARGS) >= 2 ? ARGS[2] : get(ENV, "BENCHMARK_GROUP", "ci_benchmarks")

results = run(SUITE, verbose=true)

function flatten_benchmarks(group::BenchmarkTools.BenchmarkGroup, path::Vector{String}=String[])
    results_dict = Dict{String, BenchmarkTools.Trial}()

    for (key, value) in group
        current_path = [path..., string(key)]

        if value isa BenchmarkTools.Trial
            benchmark_path = join(current_path, "/")
            results_dict[benchmark_path] = value
        elseif value isa BenchmarkTools.BenchmarkGroup
            nested_results = flatten_benchmarks(value, current_path)
            merge!(results_dict, nested_results)
        end
    end

    return results_dict
end

history = if isfile(history_file) && filesize(history_file) > 0
    JSON.parsefile(history_file)
else
    Dict{String, Any}()
end

run_timestamp = string(now())
julia_ver = string(VERSION)
commit_sha = get(ENV, "GITHUB_SHA", "unknown")
git_ref = get(ENV, "GITHUB_REF", "unknown")

flat_benchmarks = flatten_benchmarks(results)

for (benchmark_path, trial) in flat_benchmarks
    if !haskey(history, benchmark_path)
        history[benchmark_path] = Dict{String, Any}()
    end

    existing_runs = keys(history[benchmark_path])
    next_run = isempty(existing_runs) ? 1 : maximum(parse(Int, k) for k in existing_runs) + 1

    history[benchmark_path][string(next_run)] = Dict(
        "mean_time_ns" => mean(trial).time,
        "min_time_ns" => minimum(trial).time,
        "median_time_ns" => median(trial).time,
        "max_time_ns" => maximum(trial).time,
        "std_time_ns" => std(trial.times),
        "memory_bytes" => trial.memory,
        "allocs" => trial.allocs,
        "timestamp" => run_timestamp,
        "samples" => length(trial.times),
        "julia_version" => julia_ver,
        "commit_sha" => commit_sha,
        "git_ref" => git_ref
    )
end

mkpath(dirname(history_file))
open(history_file, "w") do f
    JSON.print(f, history, 2)
end
