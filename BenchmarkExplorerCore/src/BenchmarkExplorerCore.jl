module BenchmarkExplorerCore

using JSON
using Dates
using Statistics
using BenchmarkTools

export save_benchmark_results, load_history, flatten_benchmarks
export get_benchmark_names, get_subbenchmark_names, extract_timeseries_with_timestamps

function flatten_benchmarks(group::BenchmarkTools.BenchmarkGroup, path::Vector{String}=String[])
    results = Dict{String, BenchmarkTools.Trial}()

    for (key, value) in group
        current_path = [path..., string(key)]

        if value isa BenchmarkTools.Trial
            benchmark_path = join(current_path, "/")
            results[benchmark_path] = value
        elseif value isa BenchmarkTools.BenchmarkGroup
            nested_results = flatten_benchmarks(value, current_path)
            merge!(results, nested_results)
        end
    end

    return results
end

function save_benchmark_results(suite_results, history_file="data/history.json"; metadata::Dict=Dict())
    if isfile(history_file) && filesize(history_file) > 0
        history = JSON.parsefile(history_file)
    else
        history = Dict()
    end

    run_timestamp = string(now())
    julia_ver = string(VERSION)

    flat_benchmarks = flatten_benchmarks(suite_results)

    for (benchmark_path, trial) in flat_benchmarks
        if !haskey(history, benchmark_path)
            history[benchmark_path] = Dict()
        end

        existing_runs = keys(history[benchmark_path])
        next_run = isempty(existing_runs) ? 1 : maximum(parse(Int, k) for k in existing_runs) + 1

        run_data = Dict(
            "mean_time_ns" => mean(trial).time,
            "min_time_ns" => minimum(trial).time,
            "median_time_ns" => median(trial).time,
            "max_time_ns" => maximum(trial).time,
            "std_time_ns" => std(trial.times),
            "memory_bytes" => trial.memory,
            "allocs" => trial.allocs,
            "timestamp" => run_timestamp,
            "samples" => length(trial.times),
            "julia_version" => julia_ver
        )

        merge!(run_data, metadata)
        history[benchmark_path][string(next_run)] = run_data
    end

    mkpath(dirname(history_file))
    open(history_file, "w") do f
        JSON.print(f, history, 2)
    end

    return history
end

function load_history(history_file="data/history.json")
    if !isfile(history_file)
        error("File $history_file not found")
    end
    return JSON.parsefile(history_file)
end

function get_benchmark_names(history)
    top_levels = Set{String}()

    for benchmark_path in keys(history)
        parts = split(benchmark_path, "/")
        if !isempty(parts)
            push!(top_levels, parts[1])
        end
    end

    return sort(collect(top_levels))
end

function get_subbenchmark_names(history, benchmark_name)
    subbench_names = String[]

    for benchmark_path in keys(history)
        if startswith(benchmark_path, benchmark_name * "/") || benchmark_path == benchmark_name
            push!(subbench_names, benchmark_path)
        end
    end

    return sort(subbench_names)
end

function extract_timeseries_with_timestamps(history, benchmark_name, subbench_name)
    if !haskey(history, subbench_name)
        error("benchmark $subbench_name not found")
    end

    run_numbers = sort(parse.(Int, keys(history[subbench_name])))

    timestamps = DateTime[]
    mean_times = Float64[]
    min_times = Float64[]
    median_times = Float64[]
    memory = Float64[]
    allocs = Int[]

    for run_num in run_numbers
        data = history[subbench_name][string(run_num)]

        push!(timestamps, DateTime(data["timestamp"]))
        push!(mean_times, data["mean_time_ns"])
        push!(min_times, data["min_time_ns"])
        push!(median_times, data["median_time_ns"])
        push!(memory, data["memory_bytes"])
        push!(allocs, data["allocs"])
    end

    return timestamps, mean_times, min_times, median_times, memory, allocs
end

end
