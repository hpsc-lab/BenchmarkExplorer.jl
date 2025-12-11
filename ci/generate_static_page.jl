using JSON
using Dates

function generate_static_page(history_file::String, output_file::String, group_name::String, repo_url::String, commit_sha::String)
    if !isfile(history_file)
        @warn "History file not found: $history_file"
        return
    end

    history = JSON.parsefile(history_file)

    benchmarks_data = Dict{String, Any}()

    for (benchmark_name, runs) in history
        run_numbers = sort(parse.(Int, keys(runs)))

        if isempty(run_numbers)
            continue
        end

        timestamps = String[]
        mean_times = Float64[]
        min_times = Float64[]
        median_times = Float64[]
        max_times = Float64[]

        for run_num in run_numbers
            run_data = runs[string(run_num)]
            push!(timestamps, get(run_data, "timestamp", ""))
            push!(mean_times, get(run_data, "mean_time_ns", 0) / 1e6)
            push!(min_times, get(run_data, "min_time_ns", 0) / 1e6)
            push!(median_times, get(run_data, "median_time_ns", 0) / 1e6)
            push!(max_times, get(run_data, "max_time_ns", 0) / 1e6)
        end

        latest_mean = round(mean_times[end], digits=3)
        baseline_mean = length(mean_times) > 1 ? mean_times[1] : latest_mean
        percent_change = length(mean_times) > 1 ? round(((latest_mean / baseline_mean) - 1) * 100, digits=2) : 0.0

        benchmarks_data[benchmark_name] = Dict(
            "labels" => timestamps,
            "mean" => mean_times,
            "min" => min_times,
            "median" => median_times,
            "max" => max_times,
            "latest_mean" => latest_mean,
            "latest_min" => round(min_times[end], digits=3),
            "latest_memory" => get(runs[string(run_numbers[end])], "memory_bytes", 0),
            "latest_allocs" => get(runs[string(run_numbers[end])], "allocs", 0),
            "num_runs" => length(run_numbers),
            "percent_change" => percent_change,
            "trend" => percent_change > 5 ? "slower" : (percent_change < -5 ? "faster" : "stable")
        )
    end

    benchmarks_json = JSON.json(benchmarks_data)
    current_time = Dates.format(now(UTC), "yyyy-mm-dd HH:MM:SS UTC")

    html = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$group_name Benchmark Results</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
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
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }

        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }

        h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            font-weight: 700;
        }

        .subtitle {
            font-size: 1.1em;
            opacity: 0.9;
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

        .controls {
            padding: 30px 40px;
            background: #ffffff;
            border-bottom: 1px solid #dee2e6;
        }

        .controls-row {
            display: flex;
            gap: 20px;
            margin-bottom: 20px;
            flex-wrap: wrap;
            align-items: center;
        }

        .toggle-group {
            display: flex;
            gap: 10px;
            align-items: center;
            padding: 10px 15px;
            background: #f8f9fa;
            border-radius: 8px;
        }

        .toggle-group label {
            font-size: 14px;
            font-weight: 600;
            color: #495057;
            margin-right: 5px;
        }

        .toggle-btn {
            padding: 8px 16px;
            border: 2px solid #667eea;
            background: white;
            color: #667eea;
            border-radius: 6px;
            cursor: pointer;
            font-size: 13px;
            font-weight: 600;
            transition: all 0.2s;
            user-select: none;
        }

        .toggle-btn:hover {
            background: #f0f0ff;
        }

        .toggle-btn.active {
            background: #667eea;
            color: white;
        }

        .mode-btn {
            padding: 10px 20px;
            border: 2px solid #764ba2;
            background: white;
            color: #764ba2;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 600;
            transition: all 0.2s;
        }

        .mode-btn:hover {
            background: #f8f0ff;
        }

        .mode-btn.active {
            background: #764ba2;
            color: white;
        }

        .search-box {
            flex: 1;
            min-width: 250px;
            padding: 12px 20px;
            border: 2px solid #dee2e6;
            border-radius: 8px;
            font-size: 16px;
            transition: border-color 0.3s;
        }

        .search-box:focus {
            outline: none;
            border-color: #667eea;
        }

        .export-btn {
            padding: 10px 20px;
            background: #48bb78;
            color: white;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 600;
            transition: all 0.2s;
        }

        .export-btn:hover {
            background: #38a169;
        }

        body.dark-mode {
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
        }

        body.dark-mode .container {
            background: #0f172a;
            color: #e2e8f0;
        }

        body.dark-mode .meta,
        body.dark-mode .stats-grid,
        body.dark-mode .controls,
        body.dark-mode footer {
            background: #1e293b;
            border-color: #334155;
        }

        body.dark-mode .stat-card,
        body.dark-mode .benchmark-item {
            background: #1e293b;
            color: #e2e8f0;
        }

        body.dark-mode .benchmark-name {
            color: #e2e8f0;
        }

        body.dark-mode .stat-key,
        body.dark-mode .stat-label,
        body.dark-mode .meta-label {
            color: #94a3b8;
        }

        body.dark-mode .stat-val,
        body.dark-mode .meta-value {
            color: #cbd5e1;
        }

        body.dark-mode .search-box {
            background: #1e293b;
            border-color: #334155;
            color: #e2e8f0;
        }

        body.dark-mode .toggle-group {
            background: #334155;
        }

        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            padding: 20px 40px;
            background: #f8f9fa;
        }

        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }

        .stat-number {
            font-size: 2em;
            font-weight: 700;
            color: #667eea;
        }

        .stat-label {
            margin-top: 5px;
            color: #6c757d;
            font-size: 0.9em;
        }

        .benchmarks {
            padding: 40px;
        }

        .benchmark-item {
            margin-bottom: 40px;
            padding: 25px;
            background: #f8f9fa;
            border-radius: 8px;
            transition: transform 0.2s, box-shadow 0.2s;
        }

        .benchmark-item:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        }

        .benchmark-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            flex-wrap: wrap;
            gap: 15px;
        }

        .benchmark-name {
            font-size: 1.3em;
            font-weight: 600;
            color: #212529;
            font-family: 'Courier New', monospace;
            display: flex;
            align-items: center;
            gap: 10px;
            flex-wrap: wrap;
        }

        .trend-badge {
            display: inline-flex;
            align-items: center;
            gap: 5px;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.7em;
            font-weight: 700;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }

        .trend-faster {
            background: #d4edda;
            color: #155724;
        }

        .trend-slower {
            background: #f8d7da;
            color: #721c24;
        }

        .trend-stable {
            background: #d1ecf1;
            color: #0c5460;
        }

        .benchmark-stats {
            display: flex;
            gap: 20px;
            flex-wrap: wrap;
        }

        .stat {
            display: flex;
            flex-direction: column;
        }

        .stat-key {
            font-size: 0.8em;
            color: #6c757d;
            text-transform: uppercase;
        }

        .stat-val {
            font-weight: 600;
            color: #495057;
        }

        .chart-container {
            position: relative;
            height: 300px;
            margin-top: 15px;
        }

        .no-results {
            text-align: center;
            padding: 60px 20px;
            color: #6c757d;
        }

        .no-results h2 {
            margin-bottom: 10px;
        }

        footer {
            background: #f8f9fa;
            padding: 20px 40px;
            text-align: center;
            color: #6c757d;
            border-top: 1px solid #dee2e6;
        }

        @media (max-width: 768px) {
            .meta {
                flex-direction: column;
            }

            .benchmark-header {
                flex-direction: column;
                align-items: flex-start;
            }

            .chart-container {
                height: 250px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>📊 $group_name Benchmarks</h1>
            <div class="subtitle">Performance tracking over time</div>
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

        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-number" id="total-benchmarks">0</div>
                <div class="stat-label">Total Benchmarks</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" id="total-runs">0</div>
                <div class="stat-label">Total Runs</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" id="avg-time">0</div>
                <div class="stat-label">Avg Time (ms)</div>
            </div>
        </div>

        <div class="controls">
            <div class="controls-row">
                <div class="toggle-group">
                    <label>Show:</label>
                    <button class="toggle-btn active" id="toggle-mean">Mean</button>
                    <button class="toggle-btn active" id="toggle-min">Min</button>
                    <button class="toggle-btn active" id="toggle-median">Median</button>
                    <button class="toggle-btn" id="toggle-max">Max</button>
                </div>
                <button class="mode-btn" id="toggle-percentage">% Change</button>
                <button class="mode-btn" id="toggle-dark">🌙 Dark</button>
                <button class="export-btn" id="export-csv">📥 Export CSV</button>
            </div>
            <input type="text" id="search" class="search-box" placeholder="🔍 Search benchmarks...">
        </div>

        <div class="benchmarks" id="benchmarks-container"></div>

        <footer>
            <p>Generated by <a href="https://github.com/$(split(repo_url, "github.com/")[end])" target="_blank">BenchmarkExplorer</a></p>
        </footer>
    </div>

    <script>
        const benchmarksData = $benchmarks_json;

        // Calculate summary stats
        const totalBenchmarks = Object.keys(benchmarksData).length;
        let totalRuns = 0;
        let totalAvgTime = 0;

        for (const [name, data] of Object.entries(benchmarksData)) {
            totalRuns += data.num_runs;
            totalAvgTime += data.latest_mean;
        }

        document.getElementById('total-benchmarks').textContent = totalBenchmarks;
        document.getElementById('total-runs').textContent = totalRuns;
        document.getElementById('avg-time').textContent = totalBenchmarks > 0 ? (totalAvgTime / totalBenchmarks).toFixed(2) : '0';

        // Render benchmarks
        function renderBenchmarks(filter = '') {
            const container = document.getElementById('benchmarks-container');
            container.innerHTML = '';

            const filteredBenchmarks = Object.entries(benchmarksData)
                .filter(([name]) => name.toLowerCase().includes(filter.toLowerCase()))
                .sort(([a], [b]) => a.localeCompare(b));

            if (filteredBenchmarks.length === 0) {
                container.innerHTML = '<div class="no-results"><h2>No benchmarks found</h2><p>Try a different search term</p></div>';
                return;
            }

            filteredBenchmarks.forEach(([name, data], index) => {
                const item = document.createElement('div');
                item.className = 'benchmark-item';

                let trendBadge = '';
                if (data.num_runs > 1) {
                    const arrow = data.trend === 'faster' ? '↓' : (data.trend === 'slower' ? '↑' : '→');
                    const sign = data.percent_change > 0 ? '+' : '';
                    trendBadge = `<span class="trend-badge trend-\${data.trend}">\${arrow} \${sign}\${data.percent_change}%</span>`;
                }

                item.innerHTML = `
                    <div class="benchmark-header">
                        <div class="benchmark-name">
                            <span>\${name}</span>
                            \${trendBadge}
                        </div>
                        <div class="benchmark-stats">
                            <div class="stat">
                                <span class="stat-key">Latest</span>
                                <span class="stat-val">\${data.latest_mean} ms</span>
                            </div>
                            <div class="stat">
                                <span class="stat-key">Memory</span>
                                <span class="stat-val">\${formatBytes(data.latest_memory)}</span>
                            </div>
                            <div class="stat">
                                <span class="stat-key">Allocs</span>
                                <span class="stat-val">\${data.latest_allocs}</span>
                            </div>
                            <div class="stat">
                                <span class="stat-key">Runs</span>
                                <span class="stat-val">\${data.num_runs}</span>
                            </div>
                        </div>
                    </div>
                    <div class="chart-container">
                        <canvas id="chart-\${index}"></canvas>
                    </div>
                `;
                container.appendChild(item);

                // Create chart
                const ctx = document.getElementById(`chart-\${index}`).getContext('2d');

                // Process data for percentage mode
                function toPercentage(arr) {
                    if (!percentageMode || arr.length === 0) return arr;
                    const baseline = arr[0];
                    return arr.map(v => ((v / baseline) - 1) * 100);
                }

                const datasets = [];

                if (showMean) {
                    datasets.push({
                        label: 'Mean',
                        data: toPercentage(data.mean),
                        borderColor: '#667eea',
                        backgroundColor: 'rgba(102, 126, 234, 0.1)',
                        tension: 0.4,
                        fill: true
                    });
                }

                if (showMedian) {
                    datasets.push({
                        label: 'Median',
                        data: toPercentage(data.median),
                        borderColor: '#764ba2',
                        backgroundColor: 'rgba(118, 75, 162, 0.1)',
                        tension: 0.4,
                        borderDash: [5, 5]
                    });
                }

                if (showMin) {
                    datasets.push({
                        label: 'Min',
                        data: toPercentage(data.min),
                        borderColor: '#48bb78',
                        backgroundColor: 'rgba(72, 187, 120, 0.1)',
                        tension: 0.4,
                        borderDash: [2, 2]
                    });
                }

                if (showMax) {
                    datasets.push({
                        label: 'Max',
                        data: toPercentage(data.max),
                        borderColor: '#e74c3c',
                        backgroundColor: 'rgba(231, 76, 60, 0.1)',
                        tension: 0.4,
                        borderDash: [10, 5]
                    });
                }

                const chart = new Chart(ctx, {
                    type: 'line',
                    data: {
                        labels: data.labels.map((ts, i) => `Run \${i + 1}`),
                        datasets: datasets
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        plugins: {
                            legend: {
                                position: 'top',
                            },
                            tooltip: {
                                callbacks: {
                                    label: function(context) {
                                        const suffix = percentageMode ? '%' : ' ms';
                                        return context.dataset.label + ': ' + context.parsed.y.toFixed(3) + suffix;
                                    },
                                    title: function(context) {
                                        const idx = context[0].dataIndex;
                                        return data.labels[idx];
                                    }
                                }
                            }
                        },
                        scales: {
                            y: {
                                beginAtZero: !percentageMode,
                                title: {
                                    display: true,
                                    text: percentageMode ? '% Change' : 'Time (ms)'
                                }
                            }
                        }
                    }
                });

                allCharts.push(chart);
            });
        }

        function formatBytes(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }

        // Global state
        let showMean = true;
        let showMin = true;
        let showMedian = true;
        let showMax = false;
        let percentageMode = false;
        let allCharts = [];

        // Toggle buttons
        document.getElementById('toggle-mean').addEventListener('click', function() {
            showMean = !showMean;
            this.classList.toggle('active');
            updateAllCharts();
        });

        document.getElementById('toggle-min').addEventListener('click', function() {
            showMin = !showMin;
            this.classList.toggle('active');
            updateAllCharts();
        });

        document.getElementById('toggle-median').addEventListener('click', function() {
            showMedian = !showMedian;
            this.classList.toggle('active');
            updateAllCharts();
        });

        document.getElementById('toggle-max').addEventListener('click', function() {
            showMax = !showMax;
            this.classList.toggle('active');
            updateAllCharts();
        });

        document.getElementById('toggle-percentage').addEventListener('click', function() {
            percentageMode = !percentageMode;
            this.classList.toggle('active');
            updateAllCharts();
        });

        document.getElementById('toggle-dark').addEventListener('click', function() {
            document.body.classList.toggle('dark-mode');
            this.classList.toggle('active');
            updateAllCharts();
        });

        document.getElementById('export-csv').addEventListener('click', function() {
            exportToCSV();
        });

        function updateAllCharts() {
            allCharts.forEach(chart => chart.destroy());
            allCharts = [];
            renderBenchmarks(document.getElementById('search').value);
        }

        function exportToCSV() {
            let csv = 'Benchmark,Run,Timestamp,Mean(ms),Min(ms),Median(ms),Max(ms),Memory(bytes),Allocs\\n';

            for (const [name, data] of Object.entries(benchmarksData)) {
                data.labels.forEach((timestamp, idx) => {
                    csv += `"\${name}",\${idx + 1},"\${timestamp}",\${data.mean[idx]},\${data.min[idx]},\${data.median[idx]},\${data.max[idx]},\${data.latest_memory},\${data.latest_allocs}\\n`;
                });
            }

            const blob = new Blob([csv], { type: 'text/csv' });
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = '\${group_name}_benchmarks.csv';
            a.click();
            window.URL.revokeObjectURL(url);
        }

        // Initial render
        renderBenchmarks();

        // Search functionality
        document.getElementById('search').addEventListener('input', (e) => {
            renderBenchmarks(e.target.value);
        });
    </script>
</body>
</html>
"""

    open(output_file, "w") do f
        write(f, html)
    end

    println("Static page generated: $output_file")
end

# CLI usage
if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 3
        println("Usage: julia generate_static_page.jl <history_file> <output_file> <group_name> [repo_url] [commit_sha]")
        exit(1)
    end

    history_file = ARGS[1]
    output_file = ARGS[2]
    group_name = ARGS[3]
    repo_url = length(ARGS) >= 4 ? ARGS[4] : "https://github.com/unknown/repo"
    commit_sha = length(ARGS) >= 5 ? ARGS[5] : "unknown"

    generate_static_page(history_file, output_file, group_name, repo_url, commit_sha)
end
