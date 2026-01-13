module BenchmarkUI

using JSON
using Dates
using Statistics
using Printf

export DashboardData, load_dashboard_data, prepare_plot_data, calculate_stats,
       format_time_short, format_memory, get_benchmark_groups, format_time_ago,
       get_benchmark_summary, format_commit_hash

struct DashboardData
    histories::Dict{String, Any}
    groups::Vector{String}
    stats::NamedTuple
    index::Dict{String, Any}
end

function load_dashboard_data(data_dir="data")
    latest_path = joinpath(data_dir, "latest_100.json")
    index_path = joinpath(data_dir, "index.json")

    if !isfile(latest_path)
        error("Cache file $latest_path not found")
    end

    cache = JSON.parsefile(latest_path)
    histories = get(cache, "groups", Dict())

    index = isfile(index_path) ? JSON.parsefile(index_path) : Dict()

    groups = sort(collect(keys(histories)))
    stats = calculate_stats(histories)

    return DashboardData(histories, groups, stats, index)
end

function calculate_stats(histories)
    total_benchmarks = 0
    total_runs = 0
    last_run_time = nothing
    fastest_bench = ("", Inf)
    slowest_bench = ("", 0.0)

    for (group_name, history) in histories
        for (bench_path, runs) in history
            total_benchmarks += 1

            run_numbers = sort([parse(Int, k) for k in keys(runs)])
            total_runs = max(total_runs, maximum(run_numbers; init=0))

            if !isempty(run_numbers)
                latest_run = runs[string(run_numbers[end])]

                if haskey(latest_run, "timestamp")
                    run_time = DateTime(latest_run["timestamp"])
                    if isnothing(last_run_time) || run_time > last_run_time
                        last_run_time = run_time
                    end
                end

                mean_time = get(latest_run, "mean_time_ns", 0.0)
                if mean_time > 0
                    if mean_time < fastest_bench[2]
                        fastest_bench = ("$group_name/$bench_path", mean_time)
                    end
                    if mean_time > slowest_bench[2]
                        slowest_bench = ("$group_name/$bench_path", mean_time)
                    end
                end
            end
        end
    end

    return (
        total_benchmarks = total_benchmarks,
        total_runs = total_runs,
        last_run = last_run_time,
        fastest = fastest_bench,
        slowest = slowest_bench
    )
end

function prepare_plot_data(history, benchmark_path;
                          metric=:mean,
                          as_percentage=false,
                          max_runs=nothing)
    if !haskey(history, benchmark_path)
        return (x=Int[], y=Float64[], timestamps=String[], run_numbers=Int[],
                commit_hashes=String[], julia_versions=String[],
                mean=Float64[], median=Float64[], min=Float64[], max=Float64[],
                memory=Int[], allocs=Int[])
    end

    runs = history[benchmark_path]
    run_numbers = sort([parse(Int, k) for k in keys(runs)])

    if !isnothing(max_runs) && length(run_numbers) > max_runs
        run_numbers = run_numbers[end-max_runs+1:end]
    end

    timestamps = String[]
    commit_hashes = String[]
    julia_versions = String[]
    values = Float64[]

    mean_values = Float64[]
    median_values = Float64[]
    min_values = Float64[]
    max_values = Float64[]
    memory_values = Int[]
    allocs_values = Int[]

    metric_key = if metric == :mean
        "mean_time_ns"
    elseif metric == :min
        "min_time_ns"
    elseif metric == :median
        "median_time_ns"
    elseif metric == :max
        "max_time_ns"
    else
        "mean_time_ns"
    end

    baseline = nothing
    for run_num in run_numbers
        data = runs[string(run_num)]
        push!(timestamps, get(data, "timestamp", ""))
        push!(commit_hashes, get(data, "commit_hash", "unknown"))
        push!(julia_versions, get(data, "julia_version", "unknown"))

        # Collect all metrics
        push!(mean_values, get(data, "mean_time_ns", 0.0) / 1e6)
        push!(median_values, get(data, "median_time_ns", 0.0) / 1e6)
        push!(min_values, get(data, "min_time_ns", 0.0) / 1e6)
        push!(max_values, get(data, "max_time_ns", 0.0) / 1e6)
        push!(memory_values, get(data, "memory_bytes", 0))
        push!(allocs_values, get(data, "allocs", 0))

        value = get(data, metric_key, 0.0) / 1e6

        if as_percentage
            if isnothing(baseline)
                baseline = value
            end
            if baseline > 0
                value = ((value / baseline) - 1) * 100
            end
        end

        push!(values, value)
    end

    return (
        x = run_numbers,
        y = values,
        timestamps = timestamps,
        run_numbers = run_numbers,
        commit_hashes = commit_hashes,
        julia_versions = julia_versions,
        mean = mean_values,
        median = median_values,
        min = min_values,
        max = max_values,
        memory = memory_values,
        allocs = allocs_values
    )
end

function get_benchmark_groups(history)
    groups = Dict{String, Vector{String}}()

    for benchmark_path in keys(history)
        parts = split(benchmark_path, "/")
        if length(parts) >= 1
            group = parts[1]
            if !haskey(groups, group)
                groups[group] = String[]
            end
            push!(groups[group], benchmark_path)
        end
    end

    for (group, benchmarks) in groups
        groups[group] = sort(benchmarks)
    end

    return groups
end

function format_time_short(ns)
    if ns < 1e3
        if ns >= 1.0
            return @sprintf("%.0f ns", ns)
        else
            return @sprintf("%g ns", ns)
        end
    elseif ns < 1e6
        return @sprintf("%.1f μs", ns / 1e3)
    elseif ns < 1e9
        return @sprintf("%.1f ms", ns / 1e6)
    else
        return @sprintf("%.2f s", ns / 1e9)
    end
end

function format_memory(bytes)
    if bytes < 1024
        return @sprintf("%.0f B", bytes)
    elseif bytes < 1024^2
        return @sprintf("%.1f KB", bytes / 1024)
    elseif bytes < 1024^3
        return @sprintf("%.1f MB", bytes / 1024^2)
    else
        return @sprintf("%.2f GB", bytes / 1024^3)
    end
end

function format_time_ago(dt)
    if isnothing(dt)
        return "unknown"
    end

    diff = now() - dt
    hours = Dates.value(diff) / (1000 * 3600)

    if hours < 1/60
        return "just now"
    elseif hours < 1
        mins = round(Int, hours * 60)
        return mins == 1 ? "1 minute ago" : "$mins minutes ago"
    elseif hours < 24
        hrs = round(Int, hours)
        return hrs == 1 ? "1 hour ago" : "$hrs hours ago"
    else
        days = round(Int, hours / 24)
        return days == 1 ? "1 day ago" : "$days days ago"
    end
end

function get_benchmark_summary(history, benchmark_path, run_number)
    if !haskey(history, benchmark_path)
        return nothing
    end

    runs = history[benchmark_path]
    if !haskey(runs, string(run_number))
        return nothing
    end

    data = runs[string(run_number)]

    return (
        mean = get(data, "mean_time_ns", 0.0),
        median = get(data, "median_time_ns", 0.0),
        min = get(data, "min_time_ns", 0.0),
        max = get(data, "max_time_ns", 0.0),
        std = get(data, "std_time_ns", 0.0),
        memory = get(data, "memory_bytes", 0),
        allocs = get(data, "allocs", 0),
        timestamp = get(data, "timestamp", ""),
        julia_version = get(data, "julia_version", "")
    )
end

function format_commit_hash(hash::String; length::Int=7)
    if isempty(hash) || hash == "unknown"
        return "unknown"
    end
    return hash[1:min(length, Base.length(hash))]
end

end
