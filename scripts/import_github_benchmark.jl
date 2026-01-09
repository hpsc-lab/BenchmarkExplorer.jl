#!/usr/bin/env julia

using JSON
using Dates

function parse_extra(extra_str::String)
    result = Dict{String, Any}()
    for part in split(extra_str, "\n")
        if contains(part, "=")
            key, value = split(part, "=", limit=2)
            result[key] = value
        end
    end
    return result
end

function import_github_benchmark(input_file::String, group_name::String, output_dir::String="data")
    content = read(input_file, String)
    prefix = "window.BENCHMARK_DATA = "
    if startswith(content, prefix)
        content = content[length(prefix)+1:end]
    end
    content = strip(content)

    data = JSON.parse(content)
    entries = data["entries"]["Julia benchmark result"]

    mkpath(joinpath(output_dir, "by_date"))
    mkpath(joinpath(output_dir, "by_group", group_name))
    mkpath(joinpath(output_dir, "by_hash"))

    index_runs = []
    all_benchmarks = Set{String}()
    hash_count = 0

    for (run_num, entry) in enumerate(entries)
        commit_info = entry["commit"]
        commit_hash = commit_info["id"]
        timestamp_str = commit_info["timestamp"]
        timestamp = DateTime(timestamp_str[1:19])

        benchmarks = Dict{String, Any}()
        for bench in entry["benches"]
            name = bench["name"]
            push!(all_benchmarks, name)

            extra = parse_extra(get(bench, "extra", ""))
            memory = parse(Int, get(extra, "memory", "0"))
            allocs = parse(Int, get(extra, "allocs", "0"))

            benchmarks[name] = Dict(
                "mean_time_ns" => bench["value"],
                "median_time_ns" => bench["value"],
                "min_time_ns" => bench["value"],
                "max_time_ns" => bench["value"],
                "std_time_ns" => 0.0,
                "memory_bytes" => memory,
                "allocs" => allocs,
                "samples" => 1
            )
        end

        run_data = Dict(
            "metadata" => Dict(
                "run_number" => run_num,
                "group" => group_name,
                "timestamp" => string(timestamp),
                "julia_version" => "unknown",
                "commit_hash" => commit_hash
            ),
            "benchmarks" => benchmarks
        )

        group_file = joinpath(output_dir, "by_group", group_name, "run_$(run_num).json")
        open(group_file, "w") do f
            JSON.print(f, run_data, 2)
        end

        date_dir = joinpath(output_dir, "by_date",
                           Dates.format(timestamp, "yyyy-mm"),
                           Dates.format(timestamp, "dd"))
        mkpath(date_dir)

        date_file = joinpath(date_dir, "$(group_name).json")
        open(date_file, "w") do f
            JSON.print(f, run_data, 2)
        end

        if !isempty(commit_hash)
            hash_dir = joinpath(output_dir, "by_hash", commit_hash)
            mkpath(hash_dir)
            hash_file = joinpath(hash_dir, "$(group_name).json")
            open(hash_file, "w") do f
                JSON.print(f, run_data, 2)
            end
            hash_count += 1
        end

        push!(index_runs, Dict(
            "run_number" => run_num,
            "timestamp" => string(timestamp),
            "date" => Dates.format(timestamp, "yyyy-mm-dd"),
            "julia_version" => "unknown",
            "commit_hash" => commit_hash,
            "benchmark_count" => length(benchmarks),
            "file_path" => "by_group/$(group_name)/run_$(run_num).json"
        ))
    end

    index_data = Dict(
        "version" => "2.0",
        "groups" => Dict(
            group_name => Dict(
                "runs" => index_runs,
                "total_runs" => length(entries),
                "latest_run" => length(entries),
                "first_run_date" => index_runs[1]["date"],
                "last_run_date" => index_runs[end]["date"]
            )
        ),
        "last_updated" => string(now())
    )

    index_file = joinpath(output_dir, "index.json")
    open(index_file, "w") do f
        JSON.print(f, index_data, 2)
    end

    dashboard_format = Dict{String, Dict{String, Any}}()
    for name in all_benchmarks
        dashboard_format[name] = Dict{String, Any}()
    end

    for (run_num, entry) in enumerate(entries)
        commit_info = entry["commit"]
        timestamp = DateTime(commit_info["timestamp"][1:19])

        for bench in entry["benches"]
            name = bench["name"]
            extra = parse_extra(get(bench, "extra", ""))
            memory = parse(Int, get(extra, "memory", "0"))
            allocs = parse(Int, get(extra, "allocs", "0"))

            dashboard_format[name][string(run_num)] = Dict(
                "mean_time_ns" => bench["value"],
                "median_time_ns" => bench["value"],
                "min_time_ns" => bench["value"],
                "max_time_ns" => bench["value"],
                "std_time_ns" => 0.0,
                "memory_bytes" => memory,
                "allocs" => allocs,
                "samples" => 1,
                "timestamp" => string(timestamp),
                "julia_version" => "unknown"
            )
        end
    end

    latest_data = Dict(
        "version" => "2.0",
        "cached_at" => string(now()),
        "groups" => Dict(group_name => dashboard_format)
    )

    latest_file = joinpath(output_dir, "latest_100.json")
    open(latest_file, "w") do f
        JSON.print(f, latest_data, 2)
    end

    all_runs_index = Dict(
        "version" => "2.0",
        "generated_at" => string(now()),
        "groups" => Dict(
            group_name => Dict(
                "total_runs" => length(entries),
                "first_run_date" => index_runs[1]["date"],
                "last_run_date" => index_runs[end]["date"],
                "runs" => index_runs
            )
        )
    )

    all_runs_file = joinpath(output_dir, "all_runs_index.json")
    open(all_runs_file, "w") do f
        JSON.print(f, all_runs_index, 2)
    end

    return output_dir
end

function main()
    if length(ARGS) < 1
        println("""
        Usage: julia scripts/import_github_benchmark.jl <data.js> [group_name] [output_dir]

        Example:
          curl https://raw.githubusercontent.com/vchuravy/trixi-performance-tracker/gh-pages/dev/bench/data.js -o data.js
          julia scripts/import_github_benchmark.jl data.js trixi data
        """)
        exit(1)
    end

    input_file = ARGS[1]
    group_name = length(ARGS) >= 2 ? ARGS[2] : "trixi"
    output_dir = length(ARGS) >= 3 ? ARGS[3] : "data"

    import_github_benchmark(input_file, group_name, output_dir)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
