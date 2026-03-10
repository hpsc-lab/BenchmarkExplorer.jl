using JSON
using Dates

const NANOSOLDIER_REPO = "https://api.github.com/repos/JuliaCI/NanosoldierReports/contents"
const RAW_URL         = "https://raw.githubusercontent.com/JuliaCI/NanosoldierReports/master"

function gh_headers()
    token = get(ENV, "GITHUB_TOKEN", "")
    isempty(token) && return Pair{String,String}[]
    ["Authorization" => "token $token",
     "Accept"        => "application/vnd.github.v3+json"]
end

function fetch_json(url::String)
    Dl  = Base.require(Base, :Downloads)
    buf = IOBuffer()
    Dl.download(url, buf; headers=gh_headers())
    JSON.parse(String(take!(buf)))
end

function fetch_bytes(url::String)
    Dl  = Base.require(Base, :Downloads)
    buf = IOBuffer()
    Dl.download(url, buf; headers=gh_headers())
    take!(buf)
end

function _flatten!(node, prefix::String, acc::Dict)
    node isa AbstractDict || return
    if haskey(node, "times")
        times = node["times"]
        times isa Number && (times = [Float64(times)])
        times = Float64.(times)
        isempty(times) && return
        n      = length(times)
        mean_t = sum(times) / n
        s      = sort(times)
        med_t  = n % 2 == 1 ? s[n÷2+1] : (s[n÷2] + s[n÷2+1]) / 2.0
        std_t  = n > 1 ? sqrt(sum((t - mean_t)^2 for t in times) / (n-1)) : 0.0
        acc[prefix] = Dict(
            "mean_time_ns"   => mean_t,
            "min_time_ns"    => s[1],
            "median_time_ns" => med_t,
            "max_time_ns"    => s[end],
            "std_time_ns"    => std_t,
            "memory_bytes"   => Int(get(node, "memory", 0)),
            "allocs"         => Int(get(node, "allocs", 0)),
            "samples"        => n,
        )
    else
        for (k, v) in node
            k in ("params", "gctimes") && continue
            new_prefix = isempty(prefix) ? k : "$prefix/$k"
            _flatten!(v, new_prefix, acc)
        end
    end
end

function try_fetch_primary(comparison_name::String)
    url = "$RAW_URL/benchmark/by_hash/$comparison_name/primary.json.gz"
    try
        gz_path  = tempname() * ".gz"
        Dl = Base.require(Base, :Downloads)
        Dl.download(url, gz_path; headers=gh_headers())
        json_str = read(pipeline(`gunzip -c $gz_path`), String)
        rm(gz_path; force=true)
        data = JSON.parse(json_str)
        root = get(data, "benchmarks", data)
        acc  = Dict{String,Dict}()
        _flatten!(root, "", acc)
        isempty(acc) ? nothing : acc
    catch
        nothing
    end
end

function parse_report_md(content::String)
    results = Dict{String,Any}()
    for line in split(content, "\n")
        m = match(r"^\|\s*`(\[.*?\])`\s*\|\s*~?([0-9]+\.[0-9]+)", line)
        if !isnothing(m)
            results[m.captures[1]] = Dict("time_ratio"   => parse(Float64, m.captures[2]),
                                          "memory_ratio" => 1.0)
            continue
        end
        m = match(r"`(\[.*?\])`[:\s]+([0-9.]+)x", line)
        if !isnothing(m)
            results[m.captures[1]] = Dict("time_ratio"   => parse(Float64, m.captures[2]),
                                          "memory_ratio" => 1.0)
        end
    end
    results
end

function import_comparison(comparison_name::String, output_dir::String)
    outfile = joinpath(output_dir, "$comparison_name.json")
    if isfile(outfile)
        println("  Already imported: $comparison_name")
        return outfile
    end

    println("Importing: $comparison_name")
    parts = split(comparison_name, "_vs_")
    if length(parts) != 2
        @warn "Invalid comparison name: $comparison_name"
        return nothing
    end
    head_hash, base_hash = parts[1], parts[2]

    benchmarks  = try_fetch_primary(comparison_name)
    source_type = "primary_json"

    if isnothing(benchmarks)
        try
            content = String(fetch_bytes(
                "$RAW_URL/benchmark/by_hash/$comparison_name/report.md"))
            benchmarks  = parse_report_md(content)
            source_type = "report_md"
        catch e
            @warn "Failed to import $comparison_name" exception=e
            return nothing
        end
    end

    if isempty(benchmarks)
        @warn "No results found in $comparison_name"
        return nothing
    end

    println("  $(length(benchmarks)) benchmarks via $source_type")

    output = Dict(
        "metadata" => Dict(
            "comparison"  => comparison_name,
            "head_hash"   => head_hash,
            "base_hash"   => base_hash,
            "source"      => "NanosoldierReports",
            "source_type" => source_type,
            "imported_at" => string(now()),
        ),
        "benchmarks" => benchmarks,
    )
    open(outfile, "w") do f; JSON.print(f, output, 2) end
    println("  Saved: $outfile")
    outfile
end

function list_benchmark_comparisons(limit::Int=100)
    url     = "$NANOSOLDIER_REPO/benchmark/by_hash"
    entries = fetch_json(url)
    isa(entries, AbstractVector) || (@warn "Unexpected API response"; return String[])
    dirs = [e["name"] for e in entries if get(e, "type", "") == "dir"]
    reverse!(dirs)
    dirs[1:min(limit, length(dirs))]
end

function import_recent_comparisons(output_dir::String; limit::Int=10)
    mkpath(output_dir)
    candidates = list_benchmark_comparisons(limit * 4)
    println("Found $(length(candidates)) candidates (want $limit)")

    imported = String[]
    for comp in candidates
        result = import_comparison(comp, output_dir)
        !isnothing(result) && push!(imported, result)
    end

    println("\nProcessed $(length(imported)) comparisons")
    imported
end

const BASELINE_NS = 100_000_000.0

function _bench_to_explorer(bench::Dict)
    haskey(bench, "mean_time_ns") && return bench
    ratio = get(bench, "time_ratio", 1.0)
    t     = BASELINE_NS * ratio
    Dict(
        "mean_time_ns"   => t,
        "min_time_ns"    => t * 0.95,
        "median_time_ns" => t,
        "max_time_ns"    => t * 1.05,
        "std_time_ns"    => 0.0,
        "memory_bytes"   => 0,
        "allocs"         => 0,
        "samples"        => 1,
        "time_ratio"     => ratio,
    )
end

function _clean_name(name::String)
    n = replace(name, r"[\[\]\"']" => "")
    replace(n, ", " => "/")
end

function convert_to_explorer_format(nanosoldier_dir::String, output_dir::String,
                                     group_name::String="nanosoldier")
    mkpath(output_dir)
    files = sort(filter(f -> endswith(f, ".json"), readdir(nanosoldier_dir)))
    isempty(files) && (@warn "No comparison files found in $nanosoldier_dir"; return nothing)

    all_benchmarks = Dict{String,Dict}()
    run_metadata   = Dict[]
    run_number     = 1

    for file in files
        local data
        try
            data = JSON.parsefile(joinpath(nanosoldier_dir, file))
        catch e
            @warn "Could not parse $file" exception=e
            continue
        end

        meta = get(data, "metadata", Dict())

        for (name, bench) in get(data, "benchmarks", Dict())
            clean = _clean_name(name)
            haskey(all_benchmarks, clean) || (all_benchmarks[clean] = Dict())
            all_benchmarks[clean][string(run_number)] = merge(
                _bench_to_explorer(bench),
                Dict(
                    "commit_hash"   => get(meta, "head_hash",   ""),
                    "base_hash"     => get(meta, "base_hash",   ""),
                    "timestamp"     => get(meta, "imported_at", string(now())),
                    "julia_version" => "nightly",
                    "source_type"   => get(meta, "source_type", "unknown"),
                )
            )
        end

        push!(run_metadata, Dict(
            "run_number"      => run_number,
            "timestamp"       => get(meta, "imported_at", string(now())),
            "commit_hash"     => get(meta, "head_hash",   ""),
            "base_hash"       => get(meta, "base_hash",   ""),
            "benchmark_count" => length(get(data, "benchmarks", Dict())),
            "source_type"     => get(meta, "source_type", "unknown"),
        ))
        run_number += 1
    end

    categories = Dict{String, Dict{String,Dict}}()
    for (name, runs) in all_benchmarks
        cat = split(name, "/")[1]
        haskey(categories, cat) || (categories[cat] = Dict())
        categories[cat][name] = runs
    end

    groups = Dict{String,Any}()
    for (cat, benches) in sort(collect(categories), by=first)
        cat_group = "$(group_name)_$(cat)"
        cat_dir   = joinpath(output_dir, "by_group", cat_group)
        mkpath(cat_dir)
        open(joinpath(cat_dir, "history.json"), "w") do f
            JSON.print(f, benches, 2)
        end
        groups[cat_group] = benches
        println("  $cat: $(length(benches)) benchmarks")
    end

    main_dir = joinpath(output_dir, "by_group", group_name)
    mkpath(main_dir)
    open(joinpath(main_dir, "history.json"), "w") do f
        JSON.print(f, all_benchmarks, 2)
    end
    groups[group_name] = all_benchmarks

    latest_file = joinpath(output_dir, "latest_100.json")
    latest_100  = if isfile(latest_file)
        try
            JSON.parsefile(latest_file)
        catch
            Dict("version" => "2.0", "cached_at" => string(now()), "groups" => Dict())
        end
    else
        Dict("version" => "2.0", "cached_at" => string(now()), "groups" => Dict())
    end
    haskey(latest_100, "groups") || (latest_100["groups"] = Dict())
    for (k, v) in groups; latest_100["groups"][k] = v end
    open(latest_file, "w") do f; JSON.print(f, latest_100, 2) end

    index_path = joinpath(output_dir, "index.json")
    index = if isfile(index_path)
        try
            JSON.parsefile(index_path)
        catch
            Dict("version" => "2.0", "groups" => Dict(), "last_updated" => string(now()))
        end
    else
        Dict("version" => "2.0", "groups" => Dict(), "last_updated" => string(now()))
    end
    haskey(index, "groups") || (index["groups"] = Dict())

    timestamps = [rm["timestamp"] for rm in run_metadata if !isempty(get(rm, "timestamp", ""))]
    dates      = filter!(!isempty, [split(ts, "T")[1] for ts in timestamps])

    for (group_key, benches) in groups
        index["groups"][group_key] = Dict(
            "runs"           => [Dict(
                "run_number"      => rm["run_number"],
                "timestamp"       => rm["timestamp"],
                "date"            => length(rm["timestamp"]) >= 10 ? split(rm["timestamp"], "T")[1] : "",
                "julia_version"   => "nightly",
                "commit_hash"     => rm["commit_hash"],
                "benchmark_count" => get(rm, "benchmark_count", length(benches)),
                "source_type"     => get(rm, "source_type", "unknown"),
                "file_path"       => "by_group/$(group_key)/history.json",
            ) for rm in run_metadata],
            "total_runs"     => length(run_metadata),
            "latest_run"     => length(run_metadata),
            "first_run_date" => isempty(dates) ? "" : minimum(dates),
            "last_run_date"  => isempty(dates) ? "" : maximum(dates),
        )
    end
    index["last_updated"] = string(now())
    open(index_path, "w") do f; JSON.print(f, index, 2) end

    println("Converted: $(length(all_benchmarks)) benchmarks in $(length(categories)) categories")
    latest_file
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
        out   = length(ARGS) >= 2 ? ARGS[2] : "nanosoldier_data"
        limit = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 10
        import_recent_comparisons(out; limit)
    elseif cmd == "convert"
        length(ARGS) >= 3 || (println("Usage: ... convert <nanosoldier_dir> <output_dir> [group]"); exit(1))
        g = length(ARGS) >= 4 ? ARGS[4] : "nanosoldier"
        convert_to_explorer_format(ARGS[2], ARGS[3], g)
    else
        println("Unknown command: $cmd"); exit(1)
    end
end
