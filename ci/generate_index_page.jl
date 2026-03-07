using JSON
using Dates

function generate_index_page(benchmarks_dir::String, output_file::String, repo_url::String, commit_sha::String)
    index_path = joinpath(benchmarks_dir, "index.json")
    latest_path = joinpath(benchmarks_dir, "latest_100.json")

    benchmark_groups = Dict{String, Any}()

    if !isfile(index_path)
        return
    end

    index = JSON.parsefile(index_path)

    latest_data = if isfile(latest_path)
        JSON.parsefile(latest_path)
    else
        Dict("groups" => Dict())
    end

    for (group_name, group_info) in get(index, "groups", Dict())
        contains(group_name, "_") && any(startswith(group_name, p * "_") for p in ["nanosoldier", "ns"]) && continue

        num_benchmarks = if haskey(latest_data, "groups") && haskey(latest_data["groups"], group_name)
            length(latest_data["groups"][group_name])
        else
            0
        end

        benchmark_groups[group_name] = Dict(
            "num_benchmarks" => num_benchmarks,
            "total_runs" => get(group_info, "total_runs", 0),
            "latest_update" => get(group_info, "last_run_date", ""),
            "url" => "$(group_name).html"
        )
    end

    current_time = Dates.format(now(UTC), "yyyy-mm-dd HH:MM:SS UTC")

    html = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Benchmark Results</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f7f6f3;
            min-height: 100vh;
            padding: 24px;
            color: #191919;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: #fff;
            border: 1px solid #191919;
            border-radius: 12px;
            overflow: hidden;
        }

        header {
            background: #191919;
            color: #fff;
            padding: 36px 40px;
            border-bottom: 1px solid #000;
        }

        h1 {
            font-size: 1.8em;
            font-weight: 700;
            letter-spacing: -0.5px;
            margin-bottom: 6px;
        }

        .subtitle {
            font-size: 0.9em;
            color: #999;
        }

        .meta {
            background: #f7f6f3;
            padding: 14px 40px;
            border-bottom: 1px solid #e9e9e7;
            display: flex;
            gap: 24px;
            flex-wrap: wrap;
            font-size: 0.85em;
        }

        .meta-item { display: flex; align-items: center; gap: 6px; }

        .meta-label { font-weight: 600; color: #191919; }

        .meta-value { color: #787774; }

        .meta-value a { color: #191919; text-decoration: none; }

        .meta-value a:hover { text-decoration: underline; }

        .content { padding: 32px 40px; }

        .groups-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 16px;
        }

        .group-card {
            background: #fff;
            border: 1px solid #191919;
            border-radius: 10px;
            padding: 24px;
            text-decoration: none;
            color: inherit;
            display: block;
            transition: box-shadow 0.15s;
        }

        .group-card:hover {
            box-shadow: 0 2px 8px rgba(0,0,0,0.12);
        }

        .group-name {
            font-size: 1.1em;
            font-weight: 700;
            color: #191919;
            margin-bottom: 16px;
            font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
        }

        .group-stats {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 10px;
        }

        .stat-item {
            background: #f7f6f3;
            padding: 12px;
            border-radius: 8px;
            text-align: center;
        }

        .stat-number {
            font-size: 1.5em;
            font-weight: 700;
            color: #191919;
        }

        .stat-label {
            font-size: 0.75em;
            color: #787774;
            margin-top: 4px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .group-updated {
            margin-top: 14px;
            padding-top: 14px;
            border-top: 1px solid #e9e9e7;
            font-size: 0.8em;
            color: #787774;
        }

        .no-groups {
            text-align: center;
            padding: 60px 20px;
            color: #787774;
        }

        footer {
            background: #191919;
            padding: 14px 40px;
            text-align: center;
            color: #787774;
            border-top: 1px solid #000;
            font-size: 0.85em;
        }

        footer a { color: #fff; text-decoration: none; }
        footer a:hover { text-decoration: underline; }

        @media (max-width: 768px) {
            h1 { font-size: 1.4em; }
            .groups-grid { grid-template-columns: 1fr; }
            .content { padding: 24px 20px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Benchmark Dashboard</h1>
            <div class="subtitle">Performance tracking for Julia projects</div>
        </header>

        <div class="meta">
            <div class="meta-item">
                <span class="meta-label">Updated:</span>
                <span class="meta-value">$current_time</span>
            </div>
            <div class="meta-item">
                <span class="meta-label">Commit:</span>
                <span class="meta-value"><a href="$repo_url/commit/$commit_sha" target="_blank">$(commit_sha[1:min(7, length(commit_sha))])</a></span>
            </div>
            <div class="meta-item">
                <span class="meta-label">Repository:</span>
                <span class="meta-value"><a href="$repo_url" target="_blank">GitHub</a></span>
            </div>
        </div>

        <div class="content">
            <div class="groups-grid">
"""

    if isempty(benchmark_groups)
        html *= """
                <div class="no-groups">
                    <h2>No benchmark data available yet</h2>
                    <p>Benchmarks will appear here after the first CI run</p>
                </div>
"""
    else
        for (name, data) in sort(collect(benchmark_groups), by=x->x[1])
            html *= """
                <a href="$(data["url"])" class="group-card">
                    <div class="group-name">$name</div>
                    <div class="group-stats">
                        <div class="stat-item">
                            <div class="stat-number">$(data["num_benchmarks"])</div>
                            <div class="stat-label">Benchmarks</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-number">$(data["total_runs"])</div>
                            <div class="stat-label">Runs</div>
                        </div>
                    </div>
                    <div class="group-updated">Last updated: $(data["latest_update"])</div>
                </a>
"""
        end
    end

    html *= """
            </div>
        </div>

        <footer>
            <p>Powered by <a href="https://github.com/$(split(repo_url, "github.com/")[end])" target="_blank">BenchmarkExplorer</a></p>
        </footer>
    </div>
</body>
</html>
"""

    open(output_file, "w") do f
        write(f, html)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 2
        exit(1)
    end

    benchmarks_dir = ARGS[1]
    output_file = ARGS[2]
    repo_url = length(ARGS) >= 3 ? ARGS[3] : "https://github.com/unknown/repo"
    commit_sha = length(ARGS) >= 4 ? ARGS[4] : "unknown"

    generate_index_page(benchmarks_dir, output_file, repo_url, commit_sha)
end
