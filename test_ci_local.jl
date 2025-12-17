using Pkg
Pkg.activate(".")

using BenchmarkTools
using JSON
using Dates
using Statistics

const SUITE = BenchmarkGroup()

SUITE["math/addition"] = @benchmarkable 1 + 1
SUITE["math/multiplication"] = @benchmarkable 2 * 3
SUITE["array/small"] = @benchmarkable rand(10) * rand(10)'
SUITE["array/medium"] = @benchmarkable rand(100) * rand(100)'

SUITE["algorithms"] = BenchmarkGroup()
SUITE["algorithms"]["sort/small"] = @benchmarkable sort(rand(100))
SUITE["algorithms"]["sort/large"] = @benchmarkable sort(rand(1000))

tune!(SUITE)
results = run(SUITE, verbose=false, seconds=0.5, samples=10)

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

flat_benchmarks = flatten_benchmarks(results)

history_file = "data/history_test.json"

history = if isfile(history_file) && filesize(history_file) > 0
    JSON.parsefile(history_file)
else
    Dict{String, Any}()
end

run_timestamp = string(now())
julia_ver = string(VERSION)

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
        "commit_sha" => "test_local",
        "git_ref" => "refs/heads/main"
    )
end

mkpath(dirname(history_file))
open(history_file, "w") do f
    JSON.print(f, history, 2)
end

test_load = JSON.parsefile(history_file)
sample_bench = first(keys(test_load))
sample_run = first(keys(test_load[sample_bench]))
sample_data = test_load[sample_bench][sample_run]

required_fields = ["mean_time_ns", "min_time_ns", "median_time_ns",
                   "memory_bytes", "allocs", "timestamp"]

for field in required_fields
    if !haskey(sample_data, field)
        error("Missing field: $field")
    end
end
