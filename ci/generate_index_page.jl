using JSON
using Dates

function generate_index_page(benchmarks_dir::String, output_file::String, repo_url::String, commit_sha::String)
    history_files = filter(f -> endswith(f, ".json") && !contains(f, "test"), readdir(benchmarks_dir, join=true))

    benchmark_groups = Dict{String, Any}()

    for history_file in history_files
        if !isfile(history_file)
            continue
        end

        filename = basename(history_file)

        if !startswith(filename, "history_")
            continue
        end

        group_name = replace(replace(filename, "history_" => ""), ".json" => "")

        history = JSON.parsefile(history_file)
        num_benchmarks = length(history)

        total_runs = 0
        latest_time = ""

        for (benchmark_name, runs) in history
            run_numbers = parse.(Int, keys(runs))
            if !isempty(run_numbers)
                total_runs += length(run_numbers)
                latest_run = runs[string(maximum(run_numbers))]
                timestamp = get(latest_run, "timestamp", "")
                if timestamp > latest_time
                    latest_time = timestamp
                end
            end
        end

        benchmark_groups[group_name] = Dict(
            "num_benchmarks" => num_benchmarks,
            "total_runs" => total_runs,
            "latest_update" => latest_time,
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
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }

        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 60px 40px;
            text-align: center;
        }

        h1 {
            font-size: 3em;
            margin-bottom: 15px;
            font-weight: 700;
        }

        .subtitle {
            font-size: 1.2em;
            opacity: 0.9;
            margin-bottom: 30px;
        }

        .meta {
            background: #f8f9fa;
            padding: 20px 40px;
            border-bottom: 1px solid #dee2e6;
            display: flex;
            justify-content: space-between;
            flex-wrap: wrap;
            gap: 15px;
        }

        .meta-item {
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .meta-label {
            font-weight: 600;
            color: #495057;
        }

        .meta-value {
            color: #6c757d;
        }

        .meta-value a {
            color: #667eea;
            text-decoration: none;
        }

        .meta-value a:hover {
            text-decoration: underline;
        }

        .content {
            padding: 40px;
        }

        .intro {
            text-align: center;
            margin-bottom: 40px;
        }

        .intro h2 {
            color: #212529;
            margin-bottom: 15px;
        }

        .intro p {
            color: #6c757d;
            font-size: 1.1em;
        }

        .groups-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 25px;
            margin-top: 30px;
        }

        .group-card {
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            border-radius: 12px;
            padding: 30px;
            text-decoration: none;
            color: inherit;
            transition: all 0.3s ease;
            border: 2px solid transparent;
            display: block;
        }

        .group-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 30px rgba(102, 126, 234, 0.3);
            border-color: #667eea;
        }

        .group-name {
            font-size: 1.8em;
            font-weight: 700;
            color: #667eea;
            margin-bottom: 15px;
            font-family: 'Courier New', monospace;
        }

        .group-stats {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 15px;
            margin-top: 20px;
        }

        .stat-item {
            background: white;
            padding: 15px;
            border-radius: 8px;
            text-align: center;
        }

        .stat-number {
            font-size: 1.8em;
            font-weight: 700;
            color: #667eea;
        }

        .stat-label {
            font-size: 0.85em;
            color: #6c757d;
            margin-top: 5px;
        }

        .group-updated {
            margin-top: 15px;
            padding-top: 15px;
            border-top: 1px solid #dee2e6;
            font-size: 0.9em;
            color: #6c757d;
        }

        .no-groups {
            text-align: center;
            padding: 60px 20px;
            color: #6c757d;
        }

        footer {
            background: #f8f9fa;
            padding: 20px 40px;
            text-align: center;
            color: #6c757d;
            border-top: 1px solid #dee2e6;
        }

        footer a {
            color: #667eea;
            text-decoration: none;
        }

        footer a:hover {
            text-decoration: underline;
        }

        @media (max-width: 768px) {
            header h1 {
                font-size: 2em;
            }

            .groups-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>📊 Benchmark Dashboard</h1>
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
                <span class="meta-value"><a href="$repo_url" target="_blank">View on GitHub</a></span>
            </div>
        </div>

        <div class="content">
            <div class="intro">
                <h2>Available Benchmark Groups</h2>
                <p>Select a benchmark group to view detailed performance metrics and trends</p>
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
                    <div class="group-stats">
                        <div class="stat-item">
                            <div class="stat-number">$(data["num_benchmarks"])</div>
                            <div class="stat-label">Benchmarks</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-number">$(data["total_runs"])</div>
                            <div class="stat-label">Total Runs</div>
                        </div>
                    </div>
                    <div class="group-updated">
                        Last updated: $(data["latest_update"])
                    </div>
                </a>
"""
        end
    end

    html *= """
            </div>
        </div>

        <footer>
            <p>Powered by <a href="https://github.com/$(split(repo_url, "github.com/")[end])" target="_blank">BenchmarkExplorer</a></p>
            <p style="margin-top: 10px;">
                <a href="benchmarks/" target="_blank">📁 Raw Data</a>
            </p>
        </footer>
    </div>
</body>
</html>
"""

    open(output_file, "w") do f
        write(f, html)
    end

    println("Index page generated: $output_file")
end

# CLI usage
if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 2
        println("Usage: julia generate_index_page.jl <benchmarks_dir> <output_file> [repo_url] [commit_sha]")
        exit(1)
    end

    benchmarks_dir = ARGS[1]
    output_file = ARGS[2]
    repo_url = length(ARGS) >= 3 ? ARGS[3] : "https://github.com/unknown/repo"
    commit_sha = length(ARGS) >= 4 ? ARGS[4] : "unknown"

    generate_index_page(benchmarks_dir, output_file, repo_url, commit_sha)
end
