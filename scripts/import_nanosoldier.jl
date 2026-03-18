using JSON
using Dates
import Downloads

const NANOSOLDIER_REPO = "https://api.github.com/repos/JuliaCI/NanosoldierReports/contents"
const RAW_URL         = "https://raw.githubusercontent.com/JuliaCI/NanosoldierReports/master"

function gh_headers()
    token = get(ENV, "GITHUB_TOKEN", "")
    isempty(token) && return Pair{String,String}[]
    ["Authorization" => "token $token",
     "Accept"        => "application/vnd.github.v3+json"]
end

function fetch_json(url::String)
    buf = IOBuffer()
    Downloads.download(url, buf; headers=gh_headers())
    JSON.parse(String(take!(buf)))
end

function fetch_bytes(url::String)
    buf = IOBuffer()
    Downloads.download(url, buf; headers=gh_headers())
    take!(buf)
end

function _flatten_bg!(node, prefix::String, acc::Dict)
    (node isa AbstractVector && length(node) == 2) || return
    tag, payload = node[1], node[2]
    if tag == "TrialEstimate"
        payload isa AbstractDict && (acc[prefix] = payload)
    elseif tag == "BenchmarkGroup"
        payload isa AbstractDict || return
        for (k, v) in get(payload, "data", Dict())
            _flatten_bg!(v, isempty(prefix) ? k : "$prefix/$k", acc)
        end
    end
end

function _parse_bg_file(path::String)
    raw = JSON.parsefile(path)
    meta = raw[1] isa AbstractDict ? raw[1] : Dict()
    bgs  = raw[2] isa AbstractVector ? raw[2] : []
    acc  = Dict{String,Any}()
    for bg in bgs
        _flatten_bg!(bg, "", acc)
    end
    meta, acc
end

function try_fetch_data_zst(comparison_name::String)
    url = "$RAW_URL/benchmark/by_hash/$comparison_name/data.tar.zst"
    try
        zst_path = tempname() * ".tar.zst"
        Downloads.download(url, zst_path; headers=gh_headers())
        outdir = mktempdir()
        run(pipeline(`tar --use-compress-program=zstd -xf $zst_path -C $outdir`, stderr=devnull))
        rm(zst_path; force=true)

        files = readdir(outdir; join=true)
        pf = (tag) -> findfirst(f -> occursin("primary.$tag", basename(f)), files)
        mean_idx = pf("mean")
        mean_idx === nothing && return nothing

        meta, mean_acc = _parse_bg_file(files[mean_idx])
        isempty(mean_acc) && return nothing

        _, median_acc = (idx = pf("median"); idx !== nothing ? _parse_bg_file(files[idx]) : (Dict(), Dict()))
        _, min_acc    = (idx = pf("minimum"); idx !== nothing ? _parse_bg_file(files[idx]) : (Dict(), Dict()))
        _, std_acc    = (idx = pf("std"); idx !== nothing ? _parse_bg_file(files[idx]) : (Dict(), Dict()))

        ag = (tag) -> findfirst(f -> occursin("against.$tag", basename(f)), files)
        _, against_mean_acc   = (idx = ag("mean");    idx !== nothing ? _parse_bg_file(files[idx]) : (Dict(), Dict()))
        _, against_median_acc = (idx = ag("median");  idx !== nothing ? _parse_bg_file(files[idx]) : (Dict(), Dict()))
        _, against_min_acc    = (idx = ag("minimum"); idx !== nothing ? _parse_bg_file(files[idx]) : (Dict(), Dict()))

        julia_version       = get(meta, "Julia", "nightly")
        benchmarktools_ver  = get(meta, "BenchmarkTools", "")

        result = Dict{String,Dict}()
        for (name, trial) in mean_acc
            mean_t   = get(trial, "time",   0.0)
            gc_t     = get(trial, "gctime", 0.0)
            mem      = Int(get(trial, "memory", 0))
            alc      = Int(get(trial, "allocs", 0))
            median_t = get(get(median_acc, name, Dict()), "time", mean_t)
            min_t    = get(get(min_acc,    name, Dict()), "time", mean_t)
            std_t    = get(get(std_acc,    name, Dict()), "time", 0.0)

            base_trial    = get(against_mean_acc, name, Dict())
            base_mean_t   = get(base_trial, "time",   0.0)
            base_gc_t     = get(base_trial, "gctime", 0.0)
            base_mem      = Int(get(base_trial, "memory", 0))
            base_alc      = Int(get(base_trial, "allocs", 0))
            base_median_t = get(get(against_median_acc, name, Dict()), "time", 0.0)
            base_min_t    = get(get(against_min_acc,    name, Dict()), "time", 0.0)

            time_ratio    = base_mean_t   > 0 ? mean_t   / base_mean_t   : 0.0
            median_ratio  = base_median_t > 0 ? median_t / base_median_t : 0.0
            min_ratio     = base_min_t    > 0 ? min_t    / base_min_t    : 0.0
            memory_ratio  = base_mem      > 0 ? mem / base_mem           : 0.0
            allocs_ratio  = base_alc      > 0 ? alc / base_alc           : 0.0

            result[name] = Dict(
                "mean_time_ns"      => mean_t,
                "median_time_ns"    => median_t,
                "min_time_ns"       => min_t,
                "std_time_ns"       => std_t,
                "gctime_ns"         => gc_t,
                "memory_bytes"      => mem,
                "allocs"            => alc,
                "samples"           => 1,
                "base_mean_time_ns"   => base_mean_t,
                "base_median_time_ns" => base_median_t,
                "base_min_time_ns"    => base_min_t,
                "base_gctime_ns"      => base_gc_t,
                "base_memory_bytes"   => base_mem,
                "base_allocs"         => base_alc,
                "time_ratio"          => time_ratio,
                "median_ratio"        => median_ratio,
                "min_ratio"           => min_ratio,
                "memory_ratio"        => memory_ratio,
                "allocs_ratio"        => allocs_ratio,
            )
        end

        rm(outdir; force=true, recursive=true)
        isempty(result) ? nothing : (result, julia_version, benchmarktools_ver)
    catch e
        @warn "data.tar.zst unavailable for $comparison_name" exception=e
        nothing
    end
end

function parse_report_md(content::String)
    results = Dict{String,Any}()
    for line in split(content, "\n")
        m = match(r"^\|\s*`(\[.*?\])`\s*\|\s*~?([0-9]+\.[0-9]+)", line)
        if !isnothing(m)
            results[m.captures[1]] = Dict("time_ratio" => parse(Float64, m.captures[2]),
                                          "memory_ratio" => 1.0)
            continue
        end
        m = match(r"`(\[.*?\])`[:\s]+([0-9.]+)x", line)
        if !isnothing(m)
            results[m.captures[1]] = Dict("time_ratio" => parse(Float64, m.captures[2]),
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

    head_short, base_short = parts[1], parts[2]
    benchmarks    = nothing
    source_type   = "report_md"
    julia_version = "nightly"
    head_hash     = head_short
    base_hash     = base_short

    benchmarktools_ver = ""
    zst = try_fetch_data_zst(comparison_name)
    if !isnothing(zst)
        benchmarks, julia_version, benchmarktools_ver = zst
        source_type = "data_zst"
    else
        try
            content     = String(fetch_bytes("$RAW_URL/benchmark/by_hash/$comparison_name/report.md"))
            benchmarks  = parse_report_md(content)
        catch e
            @warn "Failed to import $comparison_name" exception=e
            return nothing
        end
    end

    if isempty(benchmarks)
        @warn "No results in $comparison_name"
        return nothing
    end

    commit_date    = ""
    commit_message = ""
    try
        cdata = fetch_json("https://api.github.com/repos/JuliaLang/julia/commits/$head_hash")
        if cdata isa AbstractDict
            commit_date    = get(get(get(cdata, "commit", Dict()), "author", Dict()), "date", "")
            full_msg       = get(get(cdata, "commit", Dict()), "message", "")
            commit_message = first(split(full_msg, "\n"))
        end
    catch
    end

    regression_count  = count(b -> get(b, "time_ratio", 0.0) > 1.05,  values(benchmarks))
    improvement_count = count(b -> 0 < get(b, "time_ratio", 0.0) < 0.95, values(benchmarks))
    n_with_base       = count(b -> get(b, "base_mean_time_ns", 0.0) > 0, values(benchmarks))

    println("  $(length(benchmarks)) benchmarks via $source_type (Julia $julia_version) regressions=$regression_count improvements=$improvement_count")

    output = Dict(
        "metadata" => Dict(
            "comparison"          => comparison_name,
            "head_hash"           => head_hash,
            "base_hash"           => base_hash,
            "source"              => "NanosoldierReports",
            "source_type"         => source_type,
            "julia_version"       => julia_version,
            "benchmarktools_ver"  => benchmarktools_ver,
            "commit_date"         => commit_date,
            "commit_message"      => commit_message,
            "imported_at"         => string(now()),
            "regression_count"    => regression_count,
            "improvement_count"   => improvement_count,
            "n_benchmarks"        => length(benchmarks),
            "n_with_base_data"    => n_with_base,
        ),
        "benchmarks" => benchmarks,
    )
    open(outfile, "w") do f; JSON.print(f, output, 2) end
    println("  Saved: $outfile")
    outfile
end

function list_benchmark_comparisons(limit::Int=0)
    all_dirs = String[]
    page = 1
    while true
        url = "$NANOSOLDIER_REPO/benchmark/by_hash?per_page=100&page=$page"
        entries = try
            fetch_json(url)
        catch e
            @warn "Failed to fetch page $page" exception=e
            break
        end
        isa(entries, AbstractVector) || break
        dirs = [e["name"] for e in entries if get(e, "type", "") == "dir"]
        isempty(dirs) && break
        append!(all_dirs, dirs)
        length(dirs) < 100 && break
        page += 1
    end
    reverse!(all_dirs)
    limit <= 0 ? all_dirs : all_dirs[1:min(limit, length(all_dirs))]
end

function import_recent_comparisons(output_dir::String; limit::Int=50)
    mkpath(output_dir)
    candidates = list_benchmark_comparisons(0)
    println("Found $(length(candidates)) total comparisons (want $(limit <= 0 ? "all" : string(limit)))")

    target = limit <= 0 ? length(candidates) : min(limit * 4, length(candidates))
    candidates = candidates[1:target]

    imported = String[]
    for comp in candidates
        result = import_comparison(comp, output_dir)
        !isnothing(result) && push!(imported, result)
        limit > 0 && length(imported) >= limit && break
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
        "mean_time_ns"      => t,
        "min_time_ns"       => t * 0.95,
        "median_time_ns"    => t,
        "max_time_ns"       => t * 1.05,
        "std_time_ns"       => 0.0,
        "memory_bytes"      => 0,
        "allocs"            => 0,
        "samples"           => 1,
        "time_ratio"        => ratio,
        "base_mean_time_ns" => BASELINE_NS,
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
    isempty(files) && (@warn "No comparison files in $nanosoldier_dir"; return nothing)

    seen_heads   = Dict{String,Int}()
    all_benchmarks = Dict{String,Dict}()
    run_metadata   = Dict[]
    run_number     = 1

    for file in files
        local data
        try
            data = JSON.parsefile(joinpath(nanosoldier_dir, file))
        catch e
            @warn "Cannot parse $file" exception=e
            continue
        end

        meta = get(data, "metadata", Dict())
        head = get(meta, "head_hash", "")

        if haskey(seen_heads, head) && !isempty(head)
            println("  Skipping duplicate head_hash $(head[1:min(7,end)])")
            continue
        end
        !isempty(head) && (seen_heads[head] = run_number)

        jv = get(meta, "julia_version", "nightly")

        commit_date = get(meta, "commit_date", "")
        ts = !isempty(commit_date) ? commit_date : get(meta, "imported_at", string(now()))

        for (name, bench) in get(data, "benchmarks", Dict())
            clean = _clean_name(name)
            haskey(all_benchmarks, clean) || (all_benchmarks[clean] = Dict())
            all_benchmarks[clean][string(run_number)] = merge(
                _bench_to_explorer(bench),
                Dict(
                    "commit_hash"        => head,
                    "base_hash"          => get(meta, "base_hash",    ""),
                    "timestamp"          => ts,
                    "julia_version"      => jv,
                    "source_type"        => get(meta, "source_type",  "unknown"),
                    "commit_message"     => get(meta, "commit_message", ""),
                    "benchmarktools_ver" => get(meta, "benchmarktools_ver", ""),
                )
            )
        end

        push!(run_metadata, Dict(
            "run_number"         => run_number,
            "timestamp"          => ts,
            "commit_hash"        => head,
            "base_hash"          => get(meta, "base_hash",   ""),
            "julia_version"      => jv,
            "benchmarktools_ver" => get(meta, "benchmarktools_ver", ""),
            "commit_message"     => get(meta, "commit_message", ""),
            "commit_date"        => get(meta, "commit_date", ""),
            "benchmark_count"    => get(meta, "n_benchmarks", length(get(data, "benchmarks", Dict()))),
            "n_with_base_data"   => get(meta, "n_with_base_data", 0),
            "regression_count"   => get(meta, "regression_count",  0),
            "improvement_count"  => get(meta, "improvement_count", 0),
            "source_type"        => get(meta, "source_type", "unknown"),
        ))
        run_number += 1
    end

    categories = Dict{String,Dict{String,Dict}}()
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
        try JSON.parsefile(latest_file)
        catch; Dict("version" => "2.0", "cached_at" => string(now()), "groups" => Dict()) end
    else
        Dict("version" => "2.0", "cached_at" => string(now()), "groups" => Dict())
    end
    haskey(latest_100, "groups") || (latest_100["groups"] = Dict())
    for (k, v) in groups; latest_100["groups"][k] = v end
    open(latest_file, "w") do f; JSON.print(f, latest_100, 2) end

    index_path = joinpath(output_dir, "index.json")
    index = if isfile(index_path)
        try JSON.parsefile(index_path)
        catch; Dict("version" => "2.0", "groups" => Dict(), "last_updated" => string(now())) end
    else
        Dict("version" => "2.0", "groups" => Dict(), "last_updated" => string(now()))
    end
    haskey(index, "groups") || (index["groups"] = Dict())

    timestamps = [rm["timestamp"] for rm in run_metadata if !isempty(get(rm, "timestamp", ""))]
    dates = filter!(!isempty, [split(ts, "T")[1] for ts in timestamps])

    for (group_key, benches) in groups
        index["groups"][group_key] = Dict(
            "runs"           => [Dict(
                "run_number"        => rm["run_number"],
                "timestamp"         => rm["timestamp"],
                "date"              => length(rm["timestamp"]) >= 10 ? split(rm["timestamp"], "T")[1] : "",
                "julia_version"     => get(rm, "julia_version", "nightly"),
                "commit_hash"       => rm["commit_hash"],
                "base_hash"         => get(rm, "base_hash", ""),
                "benchmark_count"   => get(rm, "benchmark_count", length(benches)),
                "source_type"       => get(rm, "source_type", "unknown"),
                "file_path"         => "by_group/$(group_key)/history.json",
                "benchmarktools_ver"=> get(rm, "benchmarktools_ver", ""),
                "commit_message"    => get(rm, "commit_message", ""),
                "commit_date"       => get(rm, "commit_date", ""),
                "n_with_base_data"  => get(rm, "n_with_base_data", 0),
                "regression_count"  => get(rm, "regression_count", 0),
                "improvement_count" => get(rm, "improvement_count", 0),
            ) for rm in run_metadata],
            "total_runs"     => length(run_metadata),
            "latest_run"     => length(run_metadata),
            "first_run_date" => isempty(dates) ? "" : minimum(dates),
            "last_run_date"  => isempty(dates) ? "" : maximum(dates),
        )
    end
    index["last_updated"] = string(now())
    open(index_path, "w") do f; JSON.print(f, index, 2) end

    n_zst = count(rm -> get(rm, "source_type", "") == "data_zst", run_metadata)
    n_md  = count(rm -> get(rm, "source_type", "") == "report_md", run_metadata)
    println("Converted: $(length(all_benchmarks)) benchmarks in $(length(categories)) categories")
    println("  Real ns (data_zst): $n_zst  |  Ratio fallback (report_md): $n_md")
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
