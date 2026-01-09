module HistoryManager

using JSON
using Dates
using Statistics
using Pkg
using BenchmarkTools
using Printf

export save_benchmark_results, load_history, get_benchmark_names,
       get_subbenchmark_names, extract_timeseries_with_timestamps,
       update_index, generate_markdown_report, load_by_hash,
       generate_all_runs_index

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

function save_benchmark_results(suite_results, group::String;
                                data_dir="data", commit_hash="")
    by_date_dir = joinpath(data_dir, "by_date")
    by_group_dir = joinpath(data_dir, "by_group", group)
    by_hash_dir = joinpath(data_dir, "by_hash")
    index_path = joinpath(data_dir, "index.json")

    mkpath(by_group_dir)

    if isfile(index_path) && filesize(index_path) > 0
        try
            index = JSON.parsefile(index_path)
        catch
            index = Dict(
                "version" => "2.0",
                "groups" => Dict(),
                "last_updated" => string(now())
            )
        end
    else
        index = Dict(
            "version" => "2.0",
            "groups" => Dict(),
            "last_updated" => string(now())
        )
    end

    if haskey(index, "groups") && haskey(index["groups"], group)
        next_run = index["groups"][group]["latest_run"] + 1
    else
        next_run = 1
    end

    run_timestamp = now()
    timestamp_str = string(run_timestamp)
    julia_ver = string(VERSION)

    flat_benchmarks = flatten_benchmarks(suite_results)

    benchmarks_dict = Dict()
    for (benchmark_path, trial) in flat_benchmarks
        benchmarks_dict[benchmark_path] = Dict(
            "mean_time_ns" => mean(trial).time,
            "median_time_ns" => median(trial).time,
            "min_time_ns" => minimum(trial).time,
            "max_time_ns" => maximum(trial).time,
            "std_time_ns" => std(trial.times),
            "memory_bytes" => trial.memory,
            "allocs" => trial.allocs,
            "samples" => length(trial.times)
        )
    end

    run_data = Dict(
        "metadata" => Dict(
            "run_number" => next_run,
            "group" => group,
            "timestamp" => timestamp_str,
            "julia_version" => julia_ver,
            "commit_hash" => commit_hash
        ),
        "benchmarks" => benchmarks_dict
    )

    by_group_path = joinpath(by_group_dir, "run_$(next_run).json")
    open(by_group_path, "w") do f
        JSON.print(f, run_data, 2)
    end

    date_str = Dates.format(run_timestamp, "yyyy-mm-dd")
    year_month = Dates.format(run_timestamp, "yyyy-mm")
    day = Dates.format(run_timestamp, "dd")

    date_dir = joinpath(by_date_dir, year_month, day)
    mkpath(date_dir)

    by_date_path = joinpath(date_dir, "$(group).json")
    open(by_date_path, "w") do f
        JSON.print(f, run_data, 2)
    end

    if !isempty(commit_hash)
        hash_dir = joinpath(by_hash_dir, commit_hash)
        mkpath(hash_dir)
        by_hash_path = joinpath(hash_dir, "$(group).json")
        open(by_hash_path, "w") do f
            JSON.print(f, run_data, 2)
        end
    end

    if !haskey(index["groups"], group)
        index["groups"][group] = Dict(
            "runs" => [],
            "total_runs" => 0,
            "latest_run" => 0,
            "first_run_date" => date_str,
            "last_run_date" => date_str
        )
    end

    push!(index["groups"][group]["runs"], Dict(
        "run_number" => next_run,
        "timestamp" => timestamp_str,
        "date" => date_str,
        "julia_version" => julia_ver,
        "commit_hash" => commit_hash,
        "benchmark_count" => length(benchmarks_dict),
        "file_path" => "by_group/$(group)/run_$(next_run).json"
    ))

    index["groups"][group]["total_runs"] = next_run
    index["groups"][group]["latest_run"] = next_run
    index["groups"][group]["last_run_date"] = date_str
    index["last_updated"] = string(now())

    open(index_path, "w") do f
        JSON.print(f, index, 2)
    end

    update_latest_cache(data_dir, group, next_run, run_data)

    prev_run_data = next_run > 1 ? load_run_data(by_group_dir, next_run - 1) : nothing
    report_content = generate_markdown_report(run_data, prev_run_data)
    report_path = joinpath(date_dir, "report.md")

    if isfile(report_path)
        open(report_path, "a") do f
            println(f, "\n---\n")
            write(f, report_content)
        end
    else
        open(report_path, "w") do f
            write(f, report_content)
        end
    end

    return run_data
end

function load_run_data(group_dir, run_number)
    path = joinpath(group_dir, "run_$(run_number).json")
    if isfile(path)
        return JSON.parsefile(path)
    end
    return nothing
end

function update_latest_cache(data_dir, group, run_number, run_data)
    cache_path = joinpath(data_dir, "latest_100.json")

    if isfile(cache_path) && filesize(cache_path) > 0
        try
            cache = JSON.parsefile(cache_path)
        catch
            cache = Dict(
                "version" => "2.0",
                "cached_at" => string(now()),
                "groups" => Dict()
            )
        end
    else
        cache = Dict(
            "version" => "2.0",
            "cached_at" => string(now()),
            "groups" => Dict()
        )
    end

    if !haskey(cache["groups"], group)
        cache["groups"][group] = Dict()
    end

    for (benchmark_path, data) in run_data["benchmarks"]
        if !haskey(cache["groups"][group], benchmark_path)
            cache["groups"][group][benchmark_path] = Dict()
        end

        cache["groups"][group][benchmark_path][string(run_number)] = Dict(
            "mean_time_ns" => data["mean_time_ns"],
            "median_time_ns" => data["median_time_ns"],
            "min_time_ns" => data["min_time_ns"],
            "max_time_ns" => data["max_time_ns"],
            "std_time_ns" => data["std_time_ns"],
            "memory_bytes" => data["memory_bytes"],
            "allocs" => data["allocs"],
            "samples" => data["samples"],
            "timestamp" => run_data["metadata"]["timestamp"],
            "julia_version" => run_data["metadata"]["julia_version"],
            "commit_hash" => get(run_data["metadata"], "commit_hash", "")
        )
    end

    cache["cached_at"] = string(now())

    open(cache_path, "w") do f
        JSON.print(f, cache, 2)
    end
end

function load_history(data_dir="data"; group=nothing)
    cache_path = joinpath(data_dir, "latest_100.json")

    if !isfile(cache_path)
        error("Cache file $cache_path not found")
    end

    cache = JSON.parsefile(cache_path)

    if isnothing(group)
        return cache["groups"]
    else
        if haskey(cache["groups"], group)
            return cache["groups"][group]
        else
            error("Group $group not found")
        end
    end
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

function generate_markdown_report(run_data, prev_run_data=nothing)
    io = IOBuffer()
    metadata = run_data["metadata"]
    benchmarks = run_data["benchmarks"]

    println(io, "# Run #$(metadata["run_number"]) - $(split(metadata["timestamp"], "T")[1])")
    println(io)
    println(io, "Julia $(metadata["julia_version"]) | $(length(benchmarks)) benchmarks")
    if haskey(metadata, "commit_hash") && !isempty(metadata["commit_hash"])
        println(io, " | $(metadata["commit_hash"][1:min(7,end)])")
    end
    println(io)

    if !isnothing(prev_run_data)
        prev_benchmarks = prev_run_data["benchmarks"]
        changes = []
        for (name, data) in benchmarks
            if haskey(prev_benchmarks, name)
                current_ms = data["mean_time_ns"] / 1e6
                prev_ms = prev_benchmarks[name]["mean_time_ns"] / 1e6
                pct_change = ((current_ms / prev_ms) - 1) * 100
                if abs(pct_change) > 5
                    push!(changes, (name, current_ms, prev_ms, pct_change))
                end
            end
        end

        if !isempty(changes)
            sort!(changes, by = x -> abs(x[4]), rev=true)
            println(io, "## Significant Changes (>5%)")
            println(io)
            println(io, "| Benchmark | Time (ms) | Prev (ms) | Change |")
            println(io, "|-----------|-----------|-----------|--------|")
            for (name, current_ms, prev_ms, pct_change) in changes[1:min(10, length(changes))]
                println(io, "| $(name) | $(@sprintf("%.3f", current_ms)) | $(@sprintf("%.3f", prev_ms)) | $(@sprintf("%+.1f", pct_change))% |")
            end
        end
    end

    return String(take!(io))
end

function update_index(data_dir="data")
    by_group_dir = joinpath(data_dir, "by_group")
    index_path = joinpath(data_dir, "index.json")

    index = Dict(
        "version" => "2.0",
        "groups" => Dict(),
        "last_updated" => string(now())
    )

    if !isdir(by_group_dir)
        error("Directory $by_group_dir not found")
    end

    for group in readdir(by_group_dir)
        group_path = joinpath(by_group_dir, group)
        if !isdir(group_path)
            continue
        end

        runs_metadata = []
        for filename in readdir(group_path)
            if !endswith(filename, ".json")
                continue
            end

            run_path = joinpath(group_path, filename)
            run_data = JSON.parsefile(run_path)

            metadata = run_data["metadata"]
            date_str = split(metadata["timestamp"], "T")[1]

            push!(runs_metadata, Dict(
                "run_number" => metadata["run_number"],
                "timestamp" => metadata["timestamp"],
                "date" => date_str,
                "julia_version" => metadata["julia_version"],
                "commit_hash" => get(metadata, "commit_hash", ""),
                "benchmark_count" => length(run_data["benchmarks"]),
                "file_path" => "by_group/$(group)/$(filename)"
            ))
        end

        sort!(runs_metadata, by = x -> x["run_number"])

        if !isempty(runs_metadata)
            index["groups"][group] = Dict(
                "runs" => runs_metadata,
                "total_runs" => length(runs_metadata),
                "latest_run" => maximum(r["run_number"] for r in runs_metadata),
                "first_run_date" => minimum(r["date"] for r in runs_metadata),
                "last_run_date" => maximum(r["date"] for r in runs_metadata)
            )
        end
    end

    open(index_path, "w") do f
        JSON.print(f, index, 2)
    end

    return index
end

function load_by_hash(commit_hash::String, group::String=""; data_dir="data")
    by_hash_dir = joinpath(data_dir, "by_hash")

    if !isdir(by_hash_dir)
        return nothing
    end

    hash_dirs = readdir(by_hash_dir)
    matching_hash = nothing

    for h in hash_dirs
        if startswith(h, commit_hash) || startswith(commit_hash, h)
            matching_hash = h
            break
        end
    end

    if isnothing(matching_hash)
        return nothing
    end

    hash_path = joinpath(by_hash_dir, matching_hash)

    if isempty(group)
        result = Dict()
        for filename in readdir(hash_path)
            if endswith(filename, ".json")
                group_name = replace(filename, ".json" => "")
                result[group_name] = JSON.parsefile(joinpath(hash_path, filename))
            end
        end
        return result
    else
        group_file = joinpath(hash_path, "$(group).json")
        if !isfile(group_file)
            return nothing
        end
        return JSON.parsefile(group_file)
    end
end

function generate_all_runs_index(data_dir="data")
    index_path = joinpath(data_dir, "index.json")

    if !isfile(index_path)
        error("index.json not found at $index_path")
    end

    index = JSON.parsefile(index_path)

    all_runs_index = Dict(
        "version" => "2.0",
        "generated_at" => string(now()),
        "groups" => Dict{String, Any}()
    )

    for (group_name, group_info) in get(index, "groups", Dict())
        runs_list = []

        for run_info in get(group_info, "runs", [])
            push!(runs_list, Dict(
                "run" => run_info["run_number"],
                "date" => run_info["date"],
                "timestamp" => run_info["timestamp"],
                "julia_version" => get(run_info, "julia_version", "unknown"),
                "commit_hash" => get(run_info, "commit_hash", "unknown"),
                "benchmark_count" => run_info["benchmark_count"],
                "url" => run_info["file_path"]
            ))
        end

        all_runs_index["groups"][group_name] = Dict(
            "total_runs" => get(group_info, "total_runs", 0),
            "first_run_date" => get(group_info, "first_run_date", ""),
            "last_run_date" => get(group_info, "last_run_date", ""),
            "runs" => runs_list
        )
    end

    output_path = joinpath(data_dir, "all_runs_index.json")
    open(output_path, "w") do f
        JSON.print(f, all_runs_index, 2)
    end

    return output_path
end

end