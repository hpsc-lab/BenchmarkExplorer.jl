using JSON
using Dates

include("../src/BenchmarkUI.jl")
using .BenchmarkUI

function format_date_nice(iso_str::String)
    try
        dt = DateTime(split(iso_str, ".")[1])
        return Dates.format(dt, "d u yyyy, HH:MM")
    catch
        return iso_str
    end
end

function generate_static_page_plotly(data_dir::String, output_file::String, group_name::String, repo_url::String, commit_sha::String)
    data = try
        load_dashboard_data(data_dir)
    catch e
        @warn "Failed to load dashboard data" exception=e
        return
    end

    if !haskey(data.histories, group_name)
        @warn "Group $group_name not found in data"
        return
    end

    history = data.histories[group_name]

    all_runs_path = joinpath(data_dir, "all_runs_index.json")
    all_runs_available = isfile(all_runs_path)

    benchmark_traces = Dict{String, Any}()

    for (benchmark_path, runs) in history
        run_numbers = sort([parse(Int, k) for k in keys(runs)])

        if isempty(run_numbers)
            continue
        end

        plot_data_mean = prepare_plot_data(history, benchmark_path; metric=:mean)
        plot_data_min = prepare_plot_data(history, benchmark_path; metric=:min)
        plot_data_median = prepare_plot_data(history, benchmark_path; metric=:median)

        latest_run = runs[string(run_numbers[end])]
        baseline_run = runs[string(run_numbers[1])]

        latest_mean = get(latest_run, "mean_time_ns", 0) / 1e6
        baseline_mean = get(baseline_run, "mean_time_ns", 1) / 1e6

        percent_change = baseline_mean > 0 ? round(((latest_mean / baseline_mean) - 1) * 100, digits=2) : 0.0

        trend = if percent_change < -5
            "faster"
        elseif percent_change > 5
            "slower"
        else
            "stable"
        end

        commit_labels = [format_commit_hash(h) for h in plot_data_mean.commit_hashes]

        hover_texts_mean = [
            "Commit: $(plot_data_mean.commit_hashes[i])<br>" *
            "Mean: $(round(plot_data_mean.mean[i], digits=3)) ms<br>" *
            "Median: $(round(plot_data_median.median[i], digits=3)) ms<br>" *
            "Min: $(round(plot_data_min.min[i], digits=3)) ms<br>" *
            "Memory: $(format_memory(plot_data_mean.memory[i]))<br>" *
            "Allocs: $(plot_data_mean.allocs[i])<br>" *
            "Julia: $(plot_data_mean.julia_versions[i])<br>" *
            "Date: $(format_date_nice(plot_data_mean.timestamps[i]))"
            for i in 1:length(plot_data_mean.y)
        ]

        benchmark_traces[benchmark_path] = Dict(
            "mean" => Dict(
                "x" => commit_labels,
                "y" => plot_data_mean.y,
                "timestamps" => plot_data_mean.timestamps,
                "commit_hashes" => plot_data_mean.commit_hashes,
                "type" => "scatter",
                "mode" => "lines+markers",
                "name" => "Mean",
                "line" => Dict("width" => 2),
                "marker" => Dict("size" => 6),
                "hovertext" => hover_texts_mean,
                "hoverinfo" => "text"
            ),
            "min" => Dict(
                "x" => commit_labels,
                "y" => plot_data_min.y,
                "type" => "scatter",
                "mode" => "lines",
                "name" => "Min",
                "line" => Dict("width" => 1, "dash" => "dash"),
                "visible" => "legendonly",
                "hovertemplate" => "Commit: %{x}<br>Min: %{y:.3f} ms<extra></extra>"
            ),
            "median" => Dict(
                "x" => commit_labels,
                "y" => plot_data_median.y,
                "type" => "scatter",
                "mode" => "lines",
                "name" => "Median",
                "line" => Dict("width" => 1, "dash" => "dot"),
                "visible" => "legendonly",
                "hovertemplate" => "Commit: %{x}<br>Median: %{y:.3f} ms<extra></extra>"
            ),
            "stats" => Dict(
                "latest_mean" => round(latest_mean, digits=3),
                "baseline_mean" => round(baseline_mean, digits=3),
                "percent_change" => percent_change,
                "trend" => trend,
                "num_runs" => length(run_numbers),
                "latest_memory" => get(latest_run, "memory_bytes", 0),
                "latest_allocs" => get(latest_run, "allocs", 0),
                "latest_timestamp" => get(latest_run, "timestamp", ""),
                "latest_commit" => get(latest_run, "commit_hash", "unknown")
            )
        )
    end

    benchmarks_json = JSON.json(benchmark_traces)
    stats_json = JSON.json(Dict(
        "total_benchmarks" => data.stats.total_benchmarks,
        "total_runs" => data.stats.total_runs,
        "fastest" => Dict(
            "name" => data.stats.fastest[1],
            "time" => format_time_short(data.stats.fastest[2])
        ),
        "slowest" => Dict(
            "name" => data.stats.slowest[1],
            "time" => format_time_short(data.stats.slowest[2])
        ),
        "last_updated" => isnothing(data.stats.last_run) ? "Unknown" : format_time_ago(data.stats.last_run)
    ))

    html = generate_html_template(benchmarks_json, stats_json, group_name, repo_url, commit_sha, all_runs_available)

    open(output_file, "w") do f
        write(f, html)
    end
end

function generate_html_template(benchmarks_json, stats_json, group_name, repo_url, commit_sha, all_runs_available)
    commit_short = commit_sha[1:min(7, length(commit_sha))]

    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>$group_name - BenchmarkExplorer</title>
        <script src="https://cdn.plot.ly/plotly-2.27.0.min.js"></script>
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }

            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                padding: 20px;
            }

            .container {
                max-width: 1600px;
                margin: 0 auto;
                background: white;
                border-radius: 20px;
                box-shadow: 0 20px 60px rgba(0,0,0,0.3);
                overflow: hidden;
            }

            header {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 40px;
                text-align: center;
            }

            header h1 {
                font-size: 3em;
                margin-bottom: 10px;
                text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
            }

            header p {
                font-size: 1.2em;
                opacity: 0.9;
            }

            .stats-panel {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                gap: 20px;
                padding: 30px;
                background: #f8f9fa;
                border-bottom: 3px solid #667eea;
            }

            .stat-card {
                background: white;
                padding: 20px;
                border-radius: 12px;
                box-shadow: 0 4px 6px rgba(0,0,0,0.1);
                text-align: center;
                transition: transform 0.3s ease, box-shadow 0.3s ease;
            }

            .stat-card:hover {
                transform: translateY(-5px);
                box-shadow: 0 8px 12px rgba(0,0,0,0.15);
            }

            .stat-card .value {
                font-size: 2.5em;
                font-weight: bold;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
                background-clip: text;
                margin-bottom: 10px;
            }

            .stat-card .label {
                color: #6c757d;
                font-size: 0.9em;
                text-transform: uppercase;
                letter-spacing: 1px;
            }

            .controls {
                padding: 30px;
                background: white;
                border-bottom: 1px solid #e9ecef;
                display: flex;
                gap: 15px;
                flex-wrap: wrap;
                align-items: center;
            }

            .btn {
                padding: 12px 24px;
                border: none;
                border-radius: 8px;
                font-size: 1em;
                cursor: pointer;
                transition: all 0.3s ease;
                font-weight: 600;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }

            .btn-primary {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
            }

            .btn-primary:hover {
                transform: translateY(-2px);
                box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
            }

            .btn-secondary {
                background: #6c757d;
                color: white;
            }

            .btn-secondary:hover {
                background: #5a6268;
            }

            .btn.active {
                background: #28a745;
            }

            .search-box {
                flex: 1;
                min-width: 300px;
                padding: 12px 20px;
                border: 2px solid #e9ecef;
                border-radius: 8px;
                font-size: 1em;
                transition: border-color 0.3s ease;
            }

            .search-box:focus {
                outline: none;
                border-color: #667eea;
            }

            .benchmarks {
                padding: 30px;
            }

            .benchmark-item {
                background: white;
                border: 2px solid #e9ecef;
                border-radius: 12px;
                margin-bottom: 30px;
                overflow: hidden;
                transition: border-color 0.3s ease, box-shadow 0.3s ease;
            }

            .benchmark-item:hover {
                border-color: #667eea;
                box-shadow: 0 4px 12px rgba(102, 126, 234, 0.1);
            }

            .benchmark-header {
                background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
                padding: 20px;
                display: flex;
                justify-content: space-between;
                align-items: center;
                flex-wrap: wrap;
                gap: 15px;
            }

            .benchmark-name {
                font-size: 1.3em;
                font-weight: bold;
                color: #2c3e50;
                display: flex;
                align-items: center;
                gap: 10px;
            }

            .trend-badge {
                padding: 6px 12px;
                border-radius: 20px;
                font-size: 0.8em;
                font-weight: bold;
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
                text-align: center;
            }

            .stat-key {
                display: block;
                font-size: 0.8em;
                color: #6c757d;
                margin-bottom: 4px;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }

            .stat-val {
                display: block;
                font-weight: bold;
                color: #2c3e50;
                font-size: 1.1em;
            }

            .plot-container {
                padding: 20px;
                min-height: 400px;
            }

            footer {
                background: #2c3e50;
                color: white;
                text-align: center;
                padding: 20px;
            }

            footer a {
                color: #667eea;
                text-decoration: none;
                font-weight: bold;
            }

            footer a:hover {
                text-decoration: underline;
            }

            .no-results {
                text-align: center;
                padding: 60px;
                color: #6c757d;
            }

            .no-results h2 {
                margin-bottom: 10px;
            }

            body.dark-mode {
                background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            }

            body.dark-mode .container {
                background: #2c3e50;
            }

            body.dark-mode .stats-panel {
                background: #34495e;
                border-bottom-color: #667eea;
            }

            body.dark-mode .stat-card {
                background: #2c3e50;
                color: #ecf0f1;
            }

            body.dark-mode .controls {
                background: #34495e;
                border-bottom-color: #4a5568;
            }

            body.dark-mode .benchmarks {
                background: #2c3e50;
            }

            body.dark-mode .benchmark-item {
                background: #34495e;
                border-color: #4a5568;
            }

            body.dark-mode .benchmark-header {
                background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%);
            }

            body.dark-mode .benchmark-name {
                color: #ecf0f1;
            }

            body.dark-mode .stat-val {
                color: #ecf0f1;
            }

            body.dark-mode .search-box {
                background: #2c3e50;
                color: #ecf0f1;
                border-color: #4a5568;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <header>
                <h1>📊 $group_name</h1>
                <p>Interactive Benchmark Dashboard • Commit: <a href="$repo_url/commit/$commit_sha" target="_blank" style="color: #a8d8ff; text-decoration: none;">$commit_short</a></p>
            </header>

            <div class="stats-panel" id="stats-panel"></div>

            <div class="controls">
                <button class="btn btn-primary" id="btn-percentage">% Change Mode</button>
                <button class="btn btn-secondary" id="btn-dark">🌙 Dark Mode</button>
                <button class="btn btn-secondary" id="btn-reset-zoom">🔍 Reset Zoom</button>
                <button class="btn btn-secondary" id="btn-export">📥 Export CSV</button>
                $(all_runs_available ? """<button class="btn btn-secondary" id="btn-load-all">📊 Load Full History</button>""" : "")
                <select id="trend-filter" class="search-box" style="min-width: 150px; flex: 0;">
                    <option value="all">All Trends</option>
                    <option value="faster">↓ Faster</option>
                    <option value="slower">↑ Slower</option>
                    <option value="stable">→ Stable</option>
                </select>
                <input type="text" id="search" class="search-box" placeholder="🔍 Search benchmarks...">
            </div>

            <div class="benchmarks" id="benchmarks-container"></div>

            <footer>
                <p>Generated by <a href="$repo_url" target="_blank">BenchmarkExplorer.jl</a> • Powered by Plotly.js</p>
                <p style="margin-top: 10px; font-size: 0.9em; opacity: 0.8;">Full interactive zoom, pan, and export capabilities</p>
            </footer>
        </div>

        <script>
            const benchmarksData = $benchmarks_json;
            const statsData = $stats_json;
            const repoUrl = '$repo_url';
            let percentageMode = false;
            let darkMode = false;
            let trendFilter = 'all';
            const renderedPlots = new Set();
            let plotObserver = null;

            function renderStats() {
                const panel = document.getElementById('stats-panel');
                panel.innerHTML = `
                    <div class="stat-card">
                        <div class="value">\${statsData.total_benchmarks}</div>
                        <div class="label">Total Benchmarks</div>
                    </div>
                    <div class="stat-card">
                        <div class="value">\${statsData.total_runs}</div>
                        <div class="label">Total Runs</div>
                    </div>
                    <div class="stat-card">
                        <div class="value" style="-webkit-text-fill-color: #27ae60;">\${statsData.fastest.time}</div>
                        <div class="label">Fastest</div>
                    </div>
                    <div class="stat-card">
                        <div class="value" style="-webkit-text-fill-color: #e74c3c;">\${statsData.slowest.time}</div>
                        <div class="label">Slowest</div>
                    </div>
                    <div class="stat-card">
                        <div class="value" style="font-size: 1.2em;">\${statsData.last_updated}</div>
                        <div class="label">Last Updated</div>
                    </div>
                `;
            }

            function formatBytes(bytes) {
                if (bytes < 1024) return bytes + ' B';
                if (bytes < 1024*1024) return (bytes/1024).toFixed(1) + ' KB';
                if (bytes < 1024*1024*1024) return (bytes/(1024*1024)).toFixed(1) + ' MB';
                return (bytes/(1024*1024*1024)).toFixed(2) + ' GB';
            }

            function formatDate(isoString) {
                if (!isoString) return '';
                const d = new Date(isoString);
                const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                const day = d.getDate();
                const month = months[d.getMonth()];
                const year = d.getFullYear();
                const hours = String(d.getHours()).padStart(2, '0');
                const mins = String(d.getMinutes()).padStart(2, '0');
                return `\${day} \${month} \${year}, \${hours}:\${mins}`;
            }

            function toPercentage(values, baselineValue) {
                if (!percentageMode || values.length === 0) return values;
                if (baselineValue === 0) return values;
                return values.map((v, i) => i === 0 ? 0 : ((v / baselineValue) - 1) * 100);
            }

            function renderSinglePlot(name, data, plotId) {
                if (renderedPlots.has(plotId)) return;
                renderedPlots.add(plotId);

                const baseline = data.mean.y[0];
                const traces = [
                    {
                        x: data.mean.x,
                        y: toPercentage(data.mean.y, baseline),
                        type: 'scatter',
                        mode: 'lines+markers',
                        name: 'Mean',
                        line: {color: '#667eea', width: 3},
                        marker: {size: 8},
                        hovertext: data.mean.hovertext,
                        hoverinfo: data.mean.hoverinfo || 'text'
                    },
                    {
                        x: data.min.x,
                        y: toPercentage(data.min.y, baseline),
                        type: 'scatter',
                        mode: 'lines',
                        name: 'Min',
                        line: {color: '#27ae60', width: 2, dash: 'dash'},
                        visible: 'legendonly',
                        hovertemplate: percentageMode ?
                            'Commit: %{x}<br>Min: %{y:.2f}%<extra></extra>' :
                            'Commit: %{x}<br>Min: %{y:.3f} ms<extra></extra>'
                    },
                    {
                        x: data.median.x,
                        y: toPercentage(data.median.y, baseline),
                        type: 'scatter',
                        mode: 'lines',
                        name: 'Median',
                        line: {color: '#f39c12', width: 2, dash: 'dot'},
                        visible: 'legendonly',
                        hovertemplate: percentageMode ?
                            'Commit: %{x}<br>Median: %{y:.2f}%<extra></extra>' :
                            'Commit: %{x}<br>Median: %{y:.3f} ms<extra></extra>'
                    }
                ];

                const layout = {
                    title: '',
                    xaxis: {
                        title: 'Commit',
                        showgrid: true,
                        zeroline: false,
                        tickangle: 45
                    },
                    yaxis: {
                        title: percentageMode ? 'Change (%)' : 'Time (ms)',
                        showgrid: true,
                        zeroline: true
                    },
                    hovermode: 'closest',
                    showlegend: true,
                    legend: {
                        x: 1,
                        xanchor: 'right',
                        y: 1
                    },
                    margin: {l: 60, r: 20, t: 20, b: 60},
                    plot_bgcolor: darkMode ? '#2c3e50' : '#ffffff',
                    paper_bgcolor: darkMode ? '#34495e' : '#ffffff',
                    font: {
                        color: darkMode ? '#ecf0f1' : '#2c3e50'
                    }
                };

                const config = {
                    responsive: true,
                    displayModeBar: true,
                    modeBarButtonsToAdd: ['hoverclosest', 'hovercompare'],
                    displaylogo: false,
                    toImageButtonOptions: {
                        format: 'png',
                        filename: name.replace(/\\//g, '_'),
                        height: 600,
                        width: 1200,
                        scale: 2
                    }
                };

                Plotly.newPlot(plotId, traces, layout, config);
            }

            function initPlotObserver() {
                if (plotObserver) plotObserver.disconnect();

                plotObserver = new IntersectionObserver((entries) => {
                    entries.forEach(entry => {
                        if (entry.isIntersecting) {
                            const plotContainer = entry.target;
                            const plotId = plotContainer.id;
                            const name = plotContainer.dataset.benchmarkName;
                            if (name && benchmarksData[name]) {
                                renderSinglePlot(name, benchmarksData[name], plotId);
                                plotObserver.unobserve(plotContainer);
                            }
                        }
                    });
                }, { rootMargin: '200px', threshold: 0 });
            }

            function renderVisiblePlots() {
                document.querySelectorAll('.plot-container[data-benchmark-name]').forEach(container => {
                    const rect = container.getBoundingClientRect();
                    if (rect.top < window.innerHeight + 200) {
                        const name = container.dataset.benchmarkName;
                        if (name && benchmarksData[name] && !renderedPlots.has(container.id)) {
                            renderSinglePlot(name, benchmarksData[name], container.id);
                        }
                    }
                });
            }

            function renderBenchmarks(filter = '') {
                const container = document.getElementById('benchmarks-container');
                container.innerHTML = '';
                renderedPlots.clear();
                initPlotObserver();

                const filtered = Object.entries(benchmarksData)
                    .filter(([name, data]) => {
                        const matchesSearch = name.toLowerCase().includes(filter.toLowerCase());
                        const matchesTrend = trendFilter === 'all' || data.stats.trend === trendFilter;
                        return matchesSearch && matchesTrend;
                    })
                    .sort(([a], [b]) => a.localeCompare(b));

                if (filtered.length === 0) {
                    container.innerHTML = '<div class="no-results"><h2>No benchmarks found</h2><p>Try a different search term</p></div>';
                    return;
                }

                filtered.forEach(([name, data]) => {
                    const stats = data.stats;
                    const item = document.createElement('div');
                    item.className = 'benchmark-item';

                    let trendBadge = '';
                    if (stats.num_runs > 1) {
                        const arrow = stats.trend === 'faster' ? '↓' : (stats.trend === 'slower' ? '↑' : '→');
                        const sign = stats.percent_change > 0 ? '+' : '';
                        trendBadge = `<span class="trend-badge trend-\${stats.trend}">\${arrow} \${sign}\${stats.percent_change}%</span>`;
                    }

                    const plotId = 'plot-' + name.replace(/[^a-zA-Z0-9]/g, '-');

                    item.innerHTML = `
                        <div class="benchmark-header">
                            <div class="benchmark-name">
                                <span>\${name}</span>
                                \${trendBadge}
                            </div>
                            <div class="benchmark-stats">
                                <div class="stat">
                                    <span class="stat-key">Latest</span>
                                    <span class="stat-val">\${stats.latest_mean} ms</span>
                                </div>
                                <div class="stat">
                                    <span class="stat-key">Commit</span>
                                    <span class="stat-val"><a href="\${repoUrl}/commit/\${stats.latest_commit}" target="_blank" style="color: #667eea; text-decoration: none;">\${stats.latest_commit.substring(0, 7)}</a></span>
                                </div>
                                <div class="stat">
                                    <span class="stat-key">Memory</span>
                                    <span class="stat-val">\${formatBytes(stats.latest_memory)}</span>
                                </div>
                                <div class="stat">
                                    <span class="stat-key">Allocs</span>
                                    <span class="stat-val">\${stats.latest_allocs}</span>
                                </div>
                                <div class="stat">
                                    <span class="stat-key">Runs</span>
                                    <span class="stat-val">\${stats.num_runs}</span>
                                </div>
                            </div>
                        </div>
                        <div class="plot-container" id="\${plotId}" data-benchmark-name="\${name}">
                            <div style="display: flex; align-items: center; justify-content: center; height: 350px; color: #6c757d;">
                                Loading chart...
                            </div>
                        </div>
                    `;
                    container.appendChild(item);

                    const plotContainer = document.getElementById(plotId);
                    plotObserver.observe(plotContainer);
                });

                setTimeout(renderVisiblePlots, 100);
            }

            function updatePercentageMode() {
                Object.entries(benchmarksData).forEach(([name, data]) => {
                    const plotId = 'plot-' + name.replace(/[^a-zA-Z0-9]/g, '-');
                    const plotDiv = document.getElementById(plotId);
                    if (!plotDiv || !plotDiv.data) return;

                    const currentVisibility = plotDiv.data.map(trace => trace.visible);

                    const newMeanY = percentageMode ?
                        data.mean.y.map((v, i) => i === 0 ? 0 : ((v / data.mean.y[0]) - 1) * 100) :
                        data.mean.y;
                    const newMinY = percentageMode ?
                        data.min.y.map((v, i) => i === 0 ? 0 : ((v / data.mean.y[0]) - 1) * 100) :
                        data.min.y;
                    const newMedianY = percentageMode ?
                        data.median.y.map((v, i) => i === 0 ? 0 : ((v / data.mean.y[0]) - 1) * 100) :
                        data.median.y;

                    const meanHoverTexts = percentageMode ?
                        data.mean.commit_hashes.map((hash, i) =>
                            \`Commit: \${hash}<br>Change: \${newMeanY[i].toFixed(2)}%<br>Original: \${data.mean.y[i].toFixed(3)} ms<br>Date: \${formatDate(data.mean.timestamps[i])}\`
                        ) : data.mean.hovertext;

                    Plotly.restyle(plotDiv, {y: [newMeanY], hovertext: [meanHoverTexts]}, [0]);
                    Plotly.restyle(plotDiv, {
                        y: [newMinY],
                        hovertemplate: percentageMode ?
                            'Commit: %{x}<br>Min: %{y:.2f}%<extra></extra>' :
                            'Commit: %{x}<br>Min: %{y:.3f} ms<extra></extra>'
                    }, [1]);
                    Plotly.restyle(plotDiv, {
                        y: [newMedianY],
                        hovertemplate: percentageMode ?
                            'Commit: %{x}<br>Median: %{y:.2f}%<extra></extra>' :
                            'Commit: %{x}<br>Median: %{y:.3f} ms<extra></extra>'
                    }, [2]);
                    Plotly.restyle(plotDiv, {visible: currentVisibility}, [0, 1, 2]);
                    Plotly.relayout(plotDiv, {
                        'yaxis.title': percentageMode ? 'Change (%)' : 'Time (ms)',
                        'yaxis.autorange': true
                    });
                });
            }

            document.getElementById('btn-percentage').addEventListener('click', function() {
                percentageMode = !percentageMode;
                this.classList.toggle('active');
                updatePercentageMode();
            });

            document.getElementById('btn-dark').addEventListener('click', function() {
                darkMode = !darkMode;
                document.body.classList.toggle('dark-mode');
                this.classList.toggle('active');
                localStorage.setItem('darkMode', darkMode);
                updatePlotColors();
            });

            function updatePlotColors() {
                Object.entries(benchmarksData).forEach(([name]) => {
                    const plotId = 'plot-' + name.replace(/[^a-zA-Z0-9]/g, '-');
                    const plotDiv = document.getElementById(plotId);
                    if (plotDiv && plotDiv.data) {
                        Plotly.relayout(plotDiv, {
                            'plot_bgcolor': darkMode ? '#2c3e50' : '#ffffff',
                            'paper_bgcolor': darkMode ? '#34495e' : '#ffffff',
                            'font.color': darkMode ? '#ecf0f1' : '#2c3e50'
                        });
                    }
                });
            }

            if (localStorage.getItem('darkMode') === 'true') {
                darkMode = true;
                document.body.classList.add('dark-mode');
                document.getElementById('btn-dark').classList.add('active');
            }

            document.getElementById('search').addEventListener('input', function(e) {
                renderBenchmarks(e.target.value);
            });

            document.getElementById('trend-filter').addEventListener('change', function(e) {
                trendFilter = e.target.value;
                renderBenchmarks(document.getElementById('search').value);
            });

            document.getElementById('btn-reset-zoom').addEventListener('click', function() {
                Object.entries(benchmarksData).forEach(([name]) => {
                    const plotId = 'plot-' + name.replace(/[^a-zA-Z0-9]/g, '-');
                    const plotDiv = document.getElementById(plotId);
                    if (plotDiv && plotDiv.data) {
                        Plotly.relayout(plotDiv, {
                            'xaxis.autorange': true,
                            'yaxis.autorange': true
                        });
                    }
                });
            });

            document.getElementById('btn-export').addEventListener('click', function() {
                let csv = 'Benchmark,Run,Timestamp,Mean (ms),Min (ms),Median (ms),Memory (bytes),Allocations\\n';

                Object.entries(benchmarksData).forEach(([name, data]) => {
                    data.mean.x.forEach((run, i) => {
                        const timestamp = data.mean.timestamps[i] || '';
                        csv += `"\${name}",\${run},\${timestamp},\${data.mean.y[i]},\${data.min.y[i]},\${data.median.y[i]},\${data.stats.latest_memory},\${data.stats.latest_allocs}\\n`;
                    });
                });

                const blob = new Blob([csv], {type: 'text/csv'});
                const url = window.URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = '$group_name-benchmarks.csv';
                a.click();
            });

            // Load full history functionality
            $(all_runs_available ? """
            let fullHistoryLoaded = false;

            document.getElementById('btn-load-all').addEventListener('click', async function() {
                if (fullHistoryLoaded) return;

                this.disabled = true;
                this.textContent = '⏳ Loading...';

                try {
                    const response = await fetch('benchmarks/all_runs_index.json');
                    const allRunsIndex = await response.json();

                    const group = allRunsIndex.groups['$group_name'];
                    if (!group) {
                        throw new Error('Group not found in index');
                    }

                    // Load all additional runs
                    for (const runInfo of group.runs) {
                        const runResponse = await fetch('benchmarks/' + runInfo.url);
                        const runData = await runResponse.json();

                        // Merge data for each benchmark
                        for (const [benchName, data] of Object.entries(runData.benchmarks)) {
                            if (!benchmarksData[benchName]) continue;

                            const commitHash = runData.metadata.commit_hash || 'unknown';
                            const commitShort = commitHash.substring(0, 7);

                            // Check if this run is already loaded
                            if (benchmarksData[benchName].mean.commit_hashes.includes(commitHash)) {
                                continue;
                            }

                            // Add new data point
                            benchmarksData[benchName].mean.x.push(commitShort);
                            benchmarksData[benchName].mean.y.push(data.mean_time_ns / 1e6);
                            benchmarksData[benchName].mean.timestamps.push(runData.metadata.timestamp);
                            benchmarksData[benchName].mean.commit_hashes.push(commitHash);

                            benchmarksData[benchName].min.x.push(commitShort);
                            benchmarksData[benchName].min.y.push(data.min_time_ns / 1e6);

                            benchmarksData[benchName].median.x.push(commitShort);
                            benchmarksData[benchName].median.y.push(data.median_time_ns / 1e6);

                            // Update hover text
                            const hoverText =
                                \`Commit: \${commitHash}<br>\` +
                                \`Mean: \${(data.mean_time_ns / 1e6).toFixed(3)} ms<br>\` +
                                \`Median: \${(data.median_time_ns / 1e6).toFixed(3)} ms<br>\` +
                                \`Min: \${(data.min_time_ns / 1e6).toFixed(3)} ms<br>\` +
                                \`Memory: \${formatBytes(data.memory_bytes)}<br>\` +
                                \`Allocs: \${data.allocs}<br>\` +
                                \`Julia: \${runData.metadata.julia_version}<br>\` +
                                \`Date: \${formatDate(runData.metadata.timestamp)}\`;

                            benchmarksData[benchName].mean.hovertext.push(hoverText);

                            // Update stats
                            benchmarksData[benchName].stats.num_runs++;
                        }
                    }

                    // Update stats panel
                    const panel = document.getElementById('stats-panel');
                    const totalRunsCard = panel.children[1];
                    if (totalRunsCard) {
                        totalRunsCard.querySelector('.value').textContent = group.total_runs;
                    }

                    fullHistoryLoaded = true;
                    this.textContent = '✅ Full History Loaded';

                    // Re-render all benchmarks with updated data
                    renderBenchmarks(document.getElementById('search').value);

                } catch (error) {
                    console.error('Failed to load full history:', error);
                    this.textContent = '❌ Load Failed';
                    this.disabled = false;
                }
            });
            """ : "")

            renderStats();
            renderBenchmarks();
        </script>
    </body>
    </html>
    """
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 4
        println("Usage: julia generate_static_page_plotly.jl <data_dir> <output_file> <group_name> <repo_url> [commit_sha]")
        exit(1)
    end

    data_dir = ARGS[1]
    output_file = ARGS[2]
    group_name = ARGS[3]
    repo_url = ARGS[4]
    commit_sha = length(ARGS) >= 5 ? ARGS[5] : "unknown"

    generate_static_page_plotly(data_dir, output_file, group_name, repo_url, commit_sha)
end
