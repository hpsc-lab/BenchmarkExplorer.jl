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
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📈</text></svg>">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: 'JetBrains Mono', 'SFMono-Regular', Consolas, monospace;
            background: #fff;
            min-height: 100vh;
            color: #191919;
            transition: background 0.2s, color 0.2s;
        }

        .container {
            max-width: 900px;
            margin: 0 auto;
            padding: 48px 32px;
            text-align: center;
        }

        .top-bar {
            display: flex;
            justify-content: flex-end;
            padding: 12px 24px;
            border-bottom: 1px solid #e9e9e7;
        }

        .btn-dark {
            background: #fff;
            border: 2px solid #191919;
            border-radius: 8px;
            padding: 6px 14px;
            font-size: 0.8em;
            font-family: inherit;
            cursor: pointer;
            font-weight: 600;
            color: #191919;
            transition: background 0.15s;
        }

        .btn-dark:hover { background: #f7f6f3; }
        .btn-dark.active { background: #191919; color: #fff; }

        h1 {
            font-size: 1.4em;
            font-weight: 700;
            color: #191919;
            margin-bottom: 8px;
        }

        .meta {
            font-size: 0.78em;
            color: #999;
            margin-bottom: 40px;
            display: flex;
            gap: 20px;
            flex-wrap: wrap;
            justify-content: center;
        }

        .meta a { color: #666; text-decoration: none; }
        .meta a:hover { text-decoration: underline; }

        .groups-grid {
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            gap: 16px;
            margin-bottom: 48px;
        }

        .group-card {
            background: #fff;
            border: 2px solid #191919;
            border-radius: 14px;
            padding: 22px 20px 18px;
            text-decoration: none;
            color: inherit;
            display: block;
            transition: box-shadow 0.15s, transform 0.15s;
            flex: 0 1 240px;
            min-width: 180px;
            text-align: left;
        }

        .group-card:hover {
            box-shadow: 0 6px 18px rgba(0,0,0,0.1);
            transform: translateY(-2px);
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
        }

        footer {
            font-size: 0.72em;
            color: #bbb;
        }

        footer a { color: #999; text-decoration: none; }
        footer a:hover { text-decoration: underline; }

        body.dark-mode { background: #191919; color: #e9e9e7; }
        body.dark-mode .top-bar { border-bottom-color: #333; }
        body.dark-mode .btn-dark { background: #252525; color: #e9e9e7; border-color: #555; }
        body.dark-mode .btn-dark:hover { background: #333; }
        body.dark-mode .btn-dark.active { background: #e9e9e7; color: #191919; border-color: #e9e9e7; }
        body.dark-mode h1 { color: #e9e9e7; }
        body.dark-mode .meta a { color: #aaa; }
        body.dark-mode .group-card { background: #252525; border-color: #383838; color: #e9e9e7; }
        body.dark-mode .group-card:hover { box-shadow: 0 6px 18px rgba(0,0,0,0.4); border-color: #666; }
        body.dark-mode .group-name { color: #aaa; }
        body.dark-mode .group-count { color: #e9e9e7; }
        body.dark-mode .group-updated { border-top-color: #333; }
        body.dark-mode footer a { color: #666; }
        body.dark-mode #search { background: #252525; color: #e9e9e7; border-color: #555; }

        @media (max-width: 600px) {
            .container { padding: 32px 16px; }
            .group-card { flex: 0 1 100%; }
        }
    </style>
</head>
<body>
    <div class="top-bar">
        <button class="btn-dark" id="btn-dark">Dark</button>
    </div>
    <div class="container">
        <h1>Benchmark Dashboard</h1>
        <div class="meta">
            <span>$current_time</span>
            <span>commit: <a href="$repo_url/commit/$commit_sha" target="_blank">$(commit_sha[1:min(7, lastindex(commit_sha))])</a></span>
            <span><a href="$repo_url" target="_blank">GitHub</a></span>
        </div>

        <input type="text" id="search" placeholder="Search groups..." style="display:block;width:100%;max-width:400px;margin:0 auto 24px;padding:10px 16px;border:2px solid #191919;border-radius:8px;font-family:inherit;font-size:0.85em;background:#fff;color:#191919;outline:none;box-sizing:border-box;">
        <div class="groups-grid" id="groups-grid">
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
            <p style="margin-top:6px;">hpsc lab</p>
        </footer>
    </div>
    <script>
        const btn = document.getElementById('btn-dark');
        function applyDark(on) {
            document.body.classList.toggle('dark-mode', on);
            btn.classList.toggle('active', on);
        }
        applyDark(localStorage.getItem('darkMode') === 'true');
        btn.addEventListener('click', function() {
            const on = !document.body.classList.contains('dark-mode');
            applyDark(on);
            localStorage.setItem('darkMode', on);
        });
        const searchEl = document.getElementById('search');
        searchEl.addEventListener('input', function() {
            const q = this.value.toLowerCase();
            document.querySelectorAll('.group-card').forEach(card => {
                card.style.display = card.querySelector('.group-name').textContent.toLowerCase().includes(q) ? '' : 'none';
            });
        });
    </script>
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
