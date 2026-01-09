using JSON
using Dates

function rebuild_latest_cache(data_dir::String="data"; max_runs::Int=100)
    index_path = joinpath(data_dir, "index.json")

    if !isfile(index_path)
        error("Index file not found: $index_path")
    end

    index = JSON.parsefile(index_path)

    cache = Dict(
        "version" => "2.0",
        "cached_at" => string(now()),
        "groups" => Dict()
    )

    for (group_name, group_info) in index["groups"]
        cache["groups"][group_name] = Dict()

        runs = group_info["runs"]
        total_runs = length(runs)
        start_run = max(1, total_runs - max_runs + 1)

        for run_info in runs[start_run:end]
            run_number = run_info["run_number"]
            run_file = joinpath(data_dir, run_info["file_path"])

            if !isfile(run_file)
                continue
            end

            run_data = JSON.parsefile(run_file)

            for (benchmark_path, bench_data) in run_data["benchmarks"]
                if !haskey(cache["groups"][group_name], benchmark_path)
                    cache["groups"][group_name][benchmark_path] = Dict()
                end

                cache["groups"][group_name][benchmark_path][string(run_number)] = Dict(
                    "mean_time_ns" => bench_data["mean_time_ns"],
                    "median_time_ns" => bench_data["median_time_ns"],
                    "min_time_ns" => bench_data["min_time_ns"],
                    "max_time_ns" => bench_data["max_time_ns"],
                    "std_time_ns" => bench_data["std_time_ns"],
                    "memory_bytes" => bench_data["memory_bytes"],
                    "allocs" => bench_data["allocs"],
                    "samples" => bench_data["samples"],
                    "timestamp" => run_data["metadata"]["timestamp"],
                    "julia_version" => run_data["metadata"]["julia_version"],
                    "commit_hash" => get(run_data["metadata"], "commit_hash", "")
                )
            end
        end
    end

    cache_path = joinpath(data_dir, "latest_100.json")
    open(cache_path, "w") do f
        JSON.print(f, cache, 2)
    end

    return cache_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    data_dir = length(ARGS) >= 1 ? ARGS[1] : "data"
    max_runs = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 100

    rebuild_latest_cache(data_dir; max_runs=max_runs)
end
