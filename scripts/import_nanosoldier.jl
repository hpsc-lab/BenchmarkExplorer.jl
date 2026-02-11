using JSON
using Dates

const NANOSOLDIER_REPO = "https://api.github.com/repos/JuliaCI/NanosoldierReports/contents"
const RAW_URL = "https://raw.githubusercontent.com/JuliaCI/NanosoldierReports/master"

function fetch_json(url::String)
    Downloads = Base.require(Base, :Downloads)
    buf = IOBuffer()
    Downloads.download(url, buf)
    return JSON.parse(String(take!(buf)))
end

function fetch_raw(url::String)
    Downloads = Base.require(Base, :Downloads)
    buf = IOBuffer()
    Downloads.download(url, buf)
    return take!(buf)
end

function list_benchmark_comparisons(limit::Int=100)
    url = "$NANOSOLDIER_REPO/benchmark/by_hash"
    entries = fetch_json(url)

    comparisons = String[]
    for entry in entries
        if entry["type"] == "dir"
            push!(comparisons, entry["name"])
        end
        length(comparisons) >= limit && break
    end

    return comparisons
end

function parse_report_md(content::String)
    results = Dict{String, Any}()

    for line in split(content, "\n")
        m = match(r"`(\[.*?\])`[:\s]+([0-9.]+)x", line)
        if !isnothing(m)
            bench_name = m.captures[1]
            time_ratio = parse(Float64, m.captures[2])
            results[bench_name] = Dict(
                "time_ratio" => time_ratio,
                "memory_ratio" => 1.0
            )
        end

        m2 = match(r"\| `(\[.*?\])` \| ([0-9.]+)", line)
        if !isnothing(m2)
            bench_name = m2.captures[1]
            time_ratio = parse(Float64, m2.captures[2])
            results[bench_name] = Dict(
                "time_ratio" => time_ratio,
                "memory_ratio" => 1.0
            )
        end
    end

    return results
end

function import_comparison(comparison_name::String, output_dir::String)
    println("Importing: $comparison_name")

    parts = split(comparison_name, "_vs_")
    if length(parts) != 2
        @warn "Invalid comparison name: $comparison_name"
        return nothing
    end

    hash1, hash2 = parts

    report_url = "$RAW_URL/benchmark/by_hash/$comparison_name/report.md"

    try
        report_content = String(fetch_raw(report_url))
        results = parse_report_md(report_content)

        if isempty(results)
            @warn "No benchmark results found in $comparison_name"
            return nothing
        end

        output = Dict(
            "metadata" => Dict(
                "comparison" => comparison_name,
                "base_hash" => hash2,
                "head_hash" => hash1,
                "source" => "NanosoldierReports",
                "imported_at" => string(now())
            ),
            "benchmarks" => results
        )

        outfile = joinpath(output_dir, "$comparison_name.json")
        open(outfile, "w") do f
            JSON.print(f, output, 2)
        end

        println("  Saved to: $outfile")
        return outfile

    catch e
        @warn "Failed to import $comparison_name" exception=e
        return nothing
    end
end

function import_recent_comparisons(output_dir::String; limit::Int=10)
    mkpath(output_dir)

    comparisons = list_benchmark_comparisons(limit)
    println("Found $(length(comparisons)) comparisons")

    imported = String[]
    for comp in comparisons
        result = import_comparison(comp, output_dir)
        !isnothing(result) && push!(imported, result)
    end

    println("\nImported $(length(imported)) comparisons")
    return imported
end

function convert_to_explorer_format(nanosoldier_dir::String, output_dir::String, group_name::String="nanosoldier")
    mkpath(output_dir)

    files = filter(f -> endswith(f, ".json"), readdir(nanosoldier_dir))

    all_benchmarks = Dict{String, Dict}()
    run_number = 1
    baseline_ns = 100_000_000.0
    run_metadata = []

    for file in sort(files)
        data = JSON.parsefile(joinpath(nanosoldier_dir, file))

        for (bench_name, bench_data) in data["benchmarks"]
            clean_name = replace(bench_name, r"[\[\]\"']" => "")
            clean_name = replace(clean_name, ", " => "/")

            if !haskey(all_benchmarks, clean_name)
                all_benchmarks[clean_name] = Dict()
            end

            ratio = get(bench_data, "time_ratio", 1.0)
            time_ns = baseline_ns * ratio

            all_benchmarks[clean_name][string(run_number)] = Dict(
                "mean_time_ns" => time_ns,
                "min_time_ns" => time_ns * 0.95,
                "median_time_ns" => time_ns,
                "max_time_ns" => time_ns * 1.05,
                "memory_bytes" => 0,
                "allocs" => 0,
                "samples" => 1,
                "commit_hash" => data["metadata"]["head_hash"],
                "timestamp" => data["metadata"]["imported_at"],
                "julia_version" => "nightly"
            )
        end

        push!(run_metadata, Dict(
            "run_number" => run_number,
            "timestamp" => get(data["metadata"], "imported_at", string(now())),
            "commit_hash" => get(data["metadata"], "head_hash", ""),
            "benchmark_count" => length(data["benchmarks"])
        ))

        run_number += 1
    end

    categories = Dict{String, Dict{String, Dict}}()
    for (bench_name, runs) in all_benchmarks
        parts = split(bench_name, "/")
        category = length(parts) > 1 ? parts[1] : "other"
        if !haskey(categories, category)
            categories[category] = Dict{String, Dict}()
        end
        categories[category][bench_name] = runs
    end

    groups = Dict{String, Any}()
    for (category, benchmarks) in categories
        cat_group = "$(group_name)_$(category)"
        cat_dir = joinpath(output_dir, "by_group", cat_group)
        mkpath(cat_dir)

        history_file = joinpath(cat_dir, "history.json")
        open(history_file, "w") do f
            JSON.print(f, benchmarks, 2)
        end

        groups[cat_group] = benchmarks
        println("  Category $category: $(length(benchmarks)) benchmarks")
    end

    mkpath(joinpath(output_dir, "by_group", group_name))
    history_file = joinpath(output_dir, "by_group", group_name, "history.json")
    open(history_file, "w") do f
        JSON.print(f, all_benchmarks, 2)
    end
    groups[group_name] = all_benchmarks

    latest_file = joinpath(output_dir, "latest_100.json")
    if isfile(latest_file) && filesize(latest_file) > 0
        try
            latest_100 = JSON.parsefile(latest_file)
            if !haskey(latest_100, "groups")
                latest_100["groups"] = Dict()
            end
        catch
            latest_100 = Dict("groups" => Dict())
        end
    else
        latest_100 = Dict("groups" => Dict())
    end
    for (k, v) in groups
        latest_100["groups"][k] = v
    end
    open(latest_file, "w") do f
        JSON.print(f, latest_100, 2)
    end

    index_path = joinpath(output_dir, "index.json")
    if isfile(index_path) && filesize(index_path) > 0
        try
            index = JSON.parsefile(index_path)
            if !haskey(index, "groups")
                index["groups"] = Dict()
            end
        catch
            index = Dict("version" => "2.0", "groups" => Dict(), "last_updated" => string(now()))
        end
    else
        index = Dict("version" => "2.0", "groups" => Dict(), "last_updated" => string(now()))
    end

    for (group_key, benchmarks) in groups
        dates = [split(rm["timestamp"], "T")[1] for rm in run_metadata]
        filter!(!isempty, dates)

        runs_list = [Dict(
            "run_number" => rm["run_number"],
            "timestamp" => rm["timestamp"],
            "date" => split(rm["timestamp"], "T")[1],
            "julia_version" => "nightly",
            "commit_hash" => rm["commit_hash"],
            "benchmark_count" => length(benchmarks),
            "file_path" => "by_group/$(group_key)/history.json"
        ) for rm in run_metadata]

        index["groups"][group_key] = Dict(
            "runs" => runs_list,
            "total_runs" => length(run_metadata),
            "latest_run" => length(run_metadata),
            "first_run_date" => isempty(dates) ? "" : minimum(dates),
            "last_run_date" => isempty(dates) ? "" : maximum(dates)
        )
    end

    index["last_updated"] = string(now())
    open(index_path, "w") do f
        JSON.print(f, index, 2)
    end

    println("Converted to Explorer format:")
    println("  Total: $(length(all_benchmarks)) benchmarks in $(length(categories)) categories")
    println("  Groups: $(join(keys(groups), ", "))")
    println("  Cache: $latest_file")
    return latest_file
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 1
        println("Usage:")
        println("  julia import_nanosoldier.jl fetch <output_dir> [limit]")
        println("  julia import_nanosoldier.jl convert <nanosoldier_dir> <output_dir> [group_name]")
        exit(1)
    end

    cmd = ARGS[1]

    if cmd == "fetch"
        output_dir = length(ARGS) >= 2 ? ARGS[2] : "nanosoldier_data"
        limit = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 10
        import_recent_comparisons(output_dir; limit=limit)

    elseif cmd == "convert"
        if length(ARGS) < 3
            println("Usage: julia import_nanosoldier.jl convert <nanosoldier_dir> <output_dir> [group_name]")
            exit(1)
        end
        nanosoldier_dir = ARGS[2]
        output_dir = ARGS[3]
        group_name = length(ARGS) >= 4 ? ARGS[4] : "nanosoldier"
        convert_to_explorer_format(nanosoldier_dir, output_dir, group_name)
    else
        println("Unknown command: $cmd")
        exit(1)
    end
end
