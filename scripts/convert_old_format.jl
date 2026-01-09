#!/usr/bin/env julia

using JSON
using Dates

function convert_old_to_new(old_file::String, group_name::String, output_dir::String="data")
    if !isfile(old_file)
        error("File not found: $old_file")
    end

    old_data = JSON.parsefile(old_file)

    mkpath(joinpath(output_dir, "by_date"))
    mkpath(joinpath(output_dir, "by_group", group_name))
    mkpath(joinpath(output_dir, "by_hash"))

    all_runs = Set{Int}()
    for (bench_path, runs) in old_data
        for run_num_str in keys(runs)
            push!(all_runs, parse(Int, run_num_str))
        end
    end

    sorted_runs = sort(collect(all_runs))
    runs_by_number = Dict{Int, Dict{String, Any}}()

    for (bench_path, runs) in old_data
        for (run_num_str, run_data) in runs
            run_num = parse(Int, run_num_str)

            if !haskey(runs_by_number, run_num)
                runs_by_number[run_num] = Dict(
                    "metadata" => Dict(
                        "run_number" => run_num,
                        "group" => group_name,
                        "timestamp" => run_data["timestamp"],
                        "julia_version" => get(run_data, "julia_version", "unknown"),
                        "commit_hash" => get(run_data, "commit_sha", get(run_data, "commit_hash", "unknown"))
                    ),
                    "benchmarks" => Dict{String, Any}()
                )
            end

            runs_by_number[run_num]["benchmarks"][bench_path] = Dict(
                "mean_time_ns" => run_data["mean_time_ns"],
                "median_time_ns" => run_data["median_time_ns"],
                "min_time_ns" => run_data["min_time_ns"],
                "max_time_ns" => run_data["max_time_ns"],
                "std_time_ns" => run_data["std_time_ns"],
                "memory_bytes" => run_data["memory_bytes"],
                "allocs" => run_data["allocs"],
                "samples" => run_data["samples"]
            )
        end
    end

    index_runs = []
    hash_count = 0

    for run_num in sorted_runs
        run_data = runs_by_number[run_num]

        group_file = joinpath(output_dir, "by_group", group_name, "run_$(run_num).json")
        open(group_file, "w") do f
            JSON.print(f, run_data, 2)
        end

        timestamp = DateTime(run_data["metadata"]["timestamp"])
        date_dir = joinpath(output_dir, "by_date",
                           Dates.format(timestamp, "yyyy-mm"),
                           Dates.format(timestamp, "dd"))
        mkpath(date_dir)

        date_file = joinpath(date_dir, "$(group_name).json")
        open(date_file, "w") do f
            JSON.print(f, run_data, 2)
        end

        commit_hash = run_data["metadata"]["commit_hash"]
        if !isempty(commit_hash) && commit_hash != "unknown"
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
            "timestamp" => run_data["metadata"]["timestamp"],
            "date" => Dates.format(timestamp, "yyyy-mm-dd"),
            "julia_version" => run_data["metadata"]["julia_version"],
            "commit_hash" => run_data["metadata"]["commit_hash"],
            "benchmark_count" => length(run_data["benchmarks"]),
            "file_path" => "by_group/$(group_name)/run_$(run_num).json"
        ))
    end

    index_data = Dict(
        "version" => "2.0",
        "groups" => Dict(
            group_name => Dict(
                "runs" => index_runs,
                "total_runs" => length(sorted_runs),
                "latest_run" => maximum(sorted_runs),
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

    latest_data = Dict(
        "version" => "2.0",
        "cached_at" => string(now()),
        "groups" => Dict{String, Any}()
    )

    dashboard_format = Dict{String, Dict{String, Any}}()

    for (bench_path, _) in old_data
        dashboard_format[bench_path] = Dict{String, Any}()
    end

    for run_num in sorted_runs
        run_data = runs_by_number[run_num]
        timestamp = run_data["metadata"]["timestamp"]
        julia_version = run_data["metadata"]["julia_version"]

        for (bench_path, bench_data) in run_data["benchmarks"]
            dashboard_format[bench_path][string(run_num)] = merge(
                bench_data,
                Dict(
                    "timestamp" => timestamp,
                    "julia_version" => julia_version
                )
            )
        end
    end

    latest_data["groups"][group_name] = dashboard_format

    latest_file = joinpath(output_dir, "latest_100.json")
    open(latest_file, "w") do f
        JSON.print(f, latest_data, 2)
    end

    all_runs_index = Dict(
        "version" => "2.0",
        "generated_at" => string(now()),
        "groups" => Dict(
            group_name => Dict(
                "total_runs" => length(sorted_runs),
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
        Usage: julia scripts/convert_old_format.jl <old_json_file> [group_name] [output_dir]

        Example:
          julia scripts/convert_old_format.jl benchmark_history.json trixi data
        """)
        exit(1)
    end

    old_file = ARGS[1]
    group_name = length(ARGS) >= 2 ? ARGS[2] : "trixi"
    output_dir = length(ARGS) >= 3 ? ARGS[3] : "data"

    convert_old_to_new(old_file, group_name, output_dir)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
