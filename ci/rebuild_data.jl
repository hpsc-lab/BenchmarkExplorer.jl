using JSON
using Dates

function rebuild_all(data_dir::String)
    by_group_dir = joinpath(data_dir, "by_group")
    if !isdir(by_group_dir)
        return
    end

    index = Dict("version" => "2.0", "groups" => Dict(), "last_updated" => string(now()))
    latest = Dict("version" => "2.0", "cached_at" => string(now()), "groups" => Dict())

    for group in readdir(by_group_dir)
        group_path = joinpath(by_group_dir, group)
        if !isdir(group_path)
            continue
        end

        history_file = joinpath(group_path, "history.json")
        run_files = filter(f -> startswith(f, "run_") && endswith(f, ".json"), readdir(group_path))

        if !isempty(run_files)
            runs_metadata = []
            latest["groups"][group] = Dict()

            for filename in sort(run_files)
                run_path = joinpath(group_path, filename)
                local run_data
                try
                    run_data = JSON.parsefile(run_path)
                catch
                    continue
                end

                if !haskey(run_data, "metadata") || !haskey(run_data, "benchmarks")
                    continue
                end

                metadata = run_data["metadata"]
                run_number = get(metadata, "run_number", 0)
                timestamp = get(metadata, "timestamp", "")
                date_str = length(timestamp) >= 10 ? split(timestamp, "T")[1] : ""

                push!(runs_metadata, Dict(
                    "run_number" => run_number,
                    "timestamp" => timestamp,
                    "date" => date_str,
                    "julia_version" => get(metadata, "julia_version", ""),
                    "commit_hash" => get(metadata, "commit_hash", ""),
                    "benchmark_count" => length(run_data["benchmarks"]),
                    "file_path" => "by_group/$(group)/$(filename)"
                ))

                for (bench_path, bench_data) in run_data["benchmarks"]
                    if !haskey(latest["groups"][group], bench_path)
                        latest["groups"][group][bench_path] = Dict()
                    end
                    latest["groups"][group][bench_path][string(run_number)] = Dict(
                        "mean_time_ns" => get(bench_data, "mean_time_ns", 0),
                        "median_time_ns" => get(bench_data, "median_time_ns", 0),
                        "min_time_ns" => get(bench_data, "min_time_ns", 0),
                        "max_time_ns" => get(bench_data, "max_time_ns", 0),
                        "std_time_ns" => get(bench_data, "std_time_ns", 0),
                        "memory_bytes" => get(bench_data, "memory_bytes", 0),
                        "allocs" => get(bench_data, "allocs", 0),
                        "samples" => get(bench_data, "samples", 0),
                        "timestamp" => timestamp,
                        "julia_version" => get(metadata, "julia_version", ""),
                        "commit_hash" => get(metadata, "commit_hash", "")
                    )
                end
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

        elseif isfile(history_file)
            local history
            try
                history = JSON.parsefile(history_file)
            catch
                continue
            end

            if !(history isa AbstractDict)
                continue
            end

            latest["groups"][group] = history

            run_numbers = Set{Int}()
            timestamps = String[]
            commit_hashes = String[]

            for (bench_name, runs) in history
                for (rn, rdata) in runs
                    n = tryparse(Int, rn)
                    if !isnothing(n)
                        push!(run_numbers, n)
                    end
                    ts = get(rdata, "timestamp", "")
                    if !isempty(ts)
                        push!(timestamps, ts)
                    end
                    ch = get(rdata, "commit_hash", "")
                    if !isempty(ch)
                        push!(commit_hashes, ch)
                    end
                end
            end

            if !isempty(run_numbers)
                dates = [length(ts) >= 10 ? split(ts, "T")[1] : "" for ts in timestamps]
                filter!(!isempty, dates)

                sorted_runs = sort(collect(run_numbers))
                runs_list = [Dict(
                    "run_number" => rn,
                    "timestamp" => !isempty(timestamps) ? timestamps[min(rn, length(timestamps))] : "",
                    "date" => !isempty(dates) ? dates[min(rn, length(dates))] : "",
                    "julia_version" => "nightly",
                    "commit_hash" => rn <= length(commit_hashes) ? commit_hashes[rn] : "",
                    "benchmark_count" => length(history),
                    "file_path" => "by_group/$(group)/history.json"
                ) for rn in sorted_runs]

                index["groups"][group] = Dict(
                    "runs" => runs_list,
                    "total_runs" => length(sorted_runs),
                    "latest_run" => maximum(sorted_runs),
                    "first_run_date" => isempty(dates) ? "" : minimum(dates),
                    "last_run_date" => isempty(dates) ? "" : maximum(dates)
                )
            end
        end
    end

    open(joinpath(data_dir, "index.json"), "w") do f
        JSON.print(f, index, 2)
    end

    open(joinpath(data_dir, "latest_100.json"), "w") do f
        JSON.print(f, latest, 2)
    end

    println("Rebuilt index.json: $(length(index["groups"])) groups")
    println("Rebuilt latest_100.json: $(length(latest["groups"])) groups")
end

if abspath(PROGRAM_FILE) == @__FILE__
    data_dir = length(ARGS) >= 1 ? ARGS[1] : "data"
    rebuild_all(data_dir)
end
