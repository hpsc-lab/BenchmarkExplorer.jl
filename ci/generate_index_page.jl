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
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: 'JetBrains Mono', 'SFMono-Regular', Consolas, monospace;
            background: #fff;
            min-height: 100vh;
            padding: 0;
            color: #191919;
        }

        .container {
            width: 100%;
            padding: 40px 48px;
        }

        h1 {
            font-size: 1.3em;
            font-weight: 700;
            color: #191919;
            margin-bottom: 6px;
        }

        .meta {
            font-size: 0.78em;
            color: #999;
            margin-bottom: 32px;
            display: flex;
            gap: 20px;
            flex-wrap: wrap;
        }

        .meta a { color: #666; text-decoration: none; }
        .meta a:hover { text-decoration: underline; }

        .groups-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 16px;
            max-width: 900px;
        }

        .group-card {
            background: #fff;
            border: 1.5px solid #191919;
            border-radius: 14px;
            padding: 22px 20px 18px;
            text-decoration: none;
            color: inherit;
            display: block;
            transition: box-shadow 0.15s;
        }

        .group-card:hover {
            box-shadow: 0 4px 14px rgba(0,0,0,0.1);
        }

        .group-name {
            font-size: 0.82em;
            color: #666;
            margin-bottom: 10px;
        }

        .group-count {
            font-size: 2.6em;
            font-weight: 700;
            color: #191919;
            line-height: 1;
            margin-bottom: 4px;
        }

        .group-runs {
            font-size: 0.72em;
            color: #aaa;
            margin-bottom: 16px;
        }

        .group-updated {
            padding-top: 12px;
            border-top: 1px solid #e9e9e7;
            font-size: 0.72em;
            color: #aaa;
        }

        .no-groups {
            text-align: center;
            padding: 60px 20px;
            color: #999;
            grid-column: 1 / -1;
        }

        footer {
            margin-top: 48px;
            font-size: 0.72em;
            color: #bbb;
        }

        footer a { color: #999; text-decoration: none; }
        footer a:hover { text-decoration: underline; }

        @media (max-width: 700px) {
            .groups-grid { grid-template-columns: 1fr; }
            body { padding: 24px 16px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Benchmark Dashboard</h1>
        <div class="meta">
            <span>$current_time</span>
            <span>commit: <a href="$repo_url/commit/$commit_sha" target="_blank">$(commit_sha[1:min(7, length(commit_sha))])</a></span>
            <span><a href="$repo_url" target="_blank">GitHub</a></span>
        </div>

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
                    <div class="group-count">$(data["num_benchmarks"])</div>
                    <div class="group-runs">$(data["total_runs"]) runs</div>
                    <div class="group-updated">$(data["latest_update"])</div>
                </a>
"""
        end
    end

    html *= """
        </div>

        <footer>
            <p>Powered by <a href="https://github.com/$(split(repo_url, "github.com/")[end])" target="_blank">BenchmarkExplorer.jl</a></p>
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
