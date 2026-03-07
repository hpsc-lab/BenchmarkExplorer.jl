using JSON
using Dates
using Statistics

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

function aggregate_by_commit(plot_data_mean, plot_data_min, plot_data_median)
    commit_order = String[]
    commit_indices = Dict{String, Vector{Int}}()

    for (i, hash) in enumerate(plot_data_mean.commit_hashes)
        if !haskey(commit_indices, hash)
            commit_indices[hash] = Int[]
            push!(commit_order, hash)
        end
        push!(commit_indices[hash], i)
    end

    agg_mean_y = Float64[]
    agg_mean_err = Float64[]
    agg_min_y = Float64[]
    agg_median_y = Float64[]
    agg_timestamps = String[]
    agg_commit_hashes = String[]
    agg_julia_versions = String[]
    agg_memory = Int[]
    agg_allocs = Int[]
    agg_n_samples = Int[]
    agg_mean_vals = Float64[]
    agg_median_vals = Float64[]
    agg_min_vals = Float64[]

    for hash in commit_order
        idx = commit_indices[hash]
        n = length(idx)

        means = [plot_data_mean.mean[i] for i in idx]
        medians = [plot_data_median.median[i] for i in idx]
        mins = [plot_data_min.min[i] for i in idx]

        push!(agg_mean_y, mean(means))
        push!(agg_mean_err, n > 1 ? std(means) : 0.0)
        push!(agg_min_y, mean(mins))
        push!(agg_median_y, mean(medians))
        push!(agg_timestamps, plot_data_mean.timestamps[idx[end]])
        push!(agg_commit_hashes, hash)
        push!(agg_julia_versions, plot_data_mean.julia_versions[idx[end]])
        push!(agg_memory, plot_data_mean.memory[idx[end]])
        push!(agg_allocs, plot_data_mean.allocs[idx[end]])
        push!(agg_n_samples, n)
        push!(agg_mean_vals, mean(means))
        push!(agg_median_vals, mean(medians))
        push!(agg_min_vals, mean(mins))
    end

    return (
        mean_y = agg_mean_y, mean_err = agg_mean_err,
        min_y = agg_min_y, median_y = agg_median_y,
        timestamps = agg_timestamps, commit_hashes = agg_commit_hashes,
        julia_versions = agg_julia_versions, memory = agg_memory,
        allocs = agg_allocs, n_samples = agg_n_samples,
        mean_vals = agg_mean_vals, median_vals = agg_median_vals,
        min_vals = agg_min_vals
    )
end

function generate_static_page_plotly(data_dir::String, output_file::String, group_name::String, repo_url::String, commit_sha::String, commit_base_url::String=repo_url)
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

        agg = aggregate_by_commit(plot_data_mean, plot_data_min, plot_data_median)

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

        commit_labels = [format_commit_hash(h) for h in agg.commit_hashes]

        hover_texts_mean = [
            "Commit: $(agg.commit_hashes[i])<br>" *
            "Mean: $(round(agg.mean_vals[i], digits=3)) ms<br>" *
            (agg.mean_err[i] > 0 ? "Std: $(round(agg.mean_err[i], digits=3)) ms<br>" : "") *
            "Median: $(round(agg.median_vals[i], digits=3)) ms<br>" *
            "Min: $(round(agg.min_vals[i], digits=3)) ms<br>" *
            "Memory: $(format_memory(agg.memory[i]))<br>" *
            "Allocs: $(agg.allocs[i])<br>" *
            "Julia: $(agg.julia_versions[i])<br>" *
            "Runs: $(agg.n_samples[i])<br>" *
            "Date: $(format_date_nice(agg.timestamps[i]))"
            for i in 1:length(agg.mean_y)
        ]

        has_errors = any(e -> e > 0, agg.mean_err)

        mean_trace = Dict(
            "x" => commit_labels,
            "y" => agg.mean_y,
            "y_raw" => agg.mean_y,
            "timestamps" => agg.timestamps,
            "commit_hashes" => agg.commit_hashes,
            "type" => "scatter",
            "mode" => "lines+markers",
            "name" => "Mean",
            "line" => Dict("width" => 2),
            "marker" => Dict("size" => 6),
            "hovertext" => hover_texts_mean,
            "hoverinfo" => "text"
        )

        if has_errors
            mean_trace["error_y"] = Dict(
                "type" => "data",
                "array" => agg.mean_err,
                "visible" => true,
                "color" => "rgba(102, 126, 234, 0.4)",
                "thickness" => 1.5,
                "width" => 4
            )
        end

        benchmark_traces[benchmark_path] = Dict(
            "mean" => mean_trace,
            "min" => Dict(
                "x" => commit_labels,
                "y" => agg.min_y,
                "y_raw" => agg.min_y,
                "type" => "scatter",
                "mode" => "lines",
                "name" => "Min",
                "line" => Dict("width" => 1, "dash" => "dash"),
                "visible" => "legendonly",
                "hovertemplate" => "Commit: %{x}<br>Min: %{y:.3f} ms<extra></extra>"
            ),
            "median" => Dict(
                "x" => commit_labels,
                "y" => agg.median_y,
                "y_raw" => agg.median_y,
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

    html = generate_html_template(benchmarks_json, stats_json, group_name, repo_url, commit_sha, all_runs_available, commit_base_url)

    open(output_file, "w") do f
        write(f, html)
    end
end

function generate_html_template(benchmarks_json, stats_json, group_name, repo_url, commit_sha, all_runs_available, commit_base_url=repo_url)
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
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: #f7f6f3;
                min-height: 100vh;
                padding: 24px;
                color: #191919;
            }

            .container {
                max-width: 1600px;
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

            header h1 {
                font-size: 2em;
                font-weight: 700;
                letter-spacing: -0.5px;
                margin-bottom: 6px;
            }

            header p {
                font-size: 0.95em;
                color: #999;
            }

            .stats-panel {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
                gap: 0;
                background: #f7f6f3;
                border-bottom: 1px solid #e9e9e7;
            }

            .stat-card {
                background: #fff;
                padding: 20px 24px;
                text-align: center;
                border-right: 1px solid #e9e9e7;
            }

            .stat-card:last-child {
                border-right: none;
            }

            .stat-card .value {
                font-size: 2em;
                font-weight: 700;
                color: #191919;
                margin-bottom: 6px;
            }

            .stat-card .label {
                color: #787774;
                font-size: 0.8em;
                text-transform: uppercase;
                letter-spacing: 0.8px;
            }

            .controls {
                padding: 16px 24px;
                background: #fff;
                border-bottom: 1px solid #e9e9e7;
                display: flex;
                gap: 10px;
                flex-wrap: wrap;
                align-items: center;
            }

            .btn {
                padding: 8px 16px;
                border: 1px solid #191919;
                border-radius: 8px;
                font-size: 0.85em;
                cursor: pointer;
                font-weight: 500;
                background: #fff;
                color: #191919;
                transition: background 0.15s;
            }

            .btn:hover {
                background: #f7f6f3;
            }

            .btn-primary {
                background: #191919;
                color: #fff;
                border-color: #191919;
            }

            .btn-primary:hover {
                background: #333;
                border-color: #333;
            }

            .btn.active {
                background: #191919;
                color: #fff;
                border-color: #191919;
            }

            .search-box {
                flex: 1;
                min-width: 260px;
                padding: 8px 14px;
                border: 1px solid #191919;
                border-radius: 8px;
                font-size: 0.9em;
                background: #fff;
                color: #191919;
            }

            .search-box:focus {
                outline: none;
                border-color: #191919;
            }

            .benchmarks {
                padding: 24px;
                background: #fff;
            }

            .benchmark-item {
                border: 1px solid #191919;
                border-radius: 10px;
                margin-bottom: 20px;
                overflow: hidden;
            }

            .benchmark-item:hover {
                box-shadow: 0 2px 8px rgba(0,0,0,0.12);
            }

            .benchmark-header {
                background: #f7f6f3;
                padding: 16px 20px;
                display: flex;
                justify-content: space-between;
                align-items: center;
                flex-wrap: wrap;
                gap: 12px;
                border-bottom: 1px solid #e9e9e7;
            }

            .benchmark-name {
                font-size: 1em;
                font-weight: 600;
                color: #191919;
                font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
                display: flex;
                align-items: center;
                gap: 10px;
            }

            .trend-badge {
                padding: 3px 8px;
                border-radius: 3px;
                font-size: 0.75em;
                font-weight: 600;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            }

            .trend-faster {
                background: #e6f4ea;
                color: #1e7e34;
                border: 1px solid #c3e6cb;
            }

            .trend-slower {
                background: #fce8e8;
                color: #b91c1c;
                border: 1px solid #f5c6cb;
            }

            .trend-stable {
                background: #f7f6f3;
                color: #787774;
                border: 1px solid #e9e9e7;
            }

            .benchmark-stats {
                display: flex;
                gap: 24px;
                flex-wrap: wrap;
            }

            .stat {
                text-align: center;
            }

            .stat-key {
                display: block;
                font-size: 0.72em;
                color: #787774;
                margin-bottom: 3px;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }

            .stat-val {
                display: block;
                font-weight: 600;
                color: #191919;
                font-size: 0.95em;
            }

            .plot-container {
                padding: 20px;
                min-height: 380px;
                background: #fff;
            }

            footer {
                background: #191919;
                color: #787774;
                text-align: center;
                padding: 16px;
                font-size: 0.85em;
            }

            footer a {
                color: #fff;
                text-decoration: none;
            }

            footer a:hover {
                text-decoration: underline;
            }

            .no-results {
                text-align: center;
                padding: 60px;
                color: #787774;
            }

            .no-results h2 {
                margin-bottom: 10px;
                color: #191919;
            }

            .tree-node {
                margin-left: 16px;
            }

            .tree-node.root {
                margin-left: 0;
            }

            .tree-toggle {
                display: flex;
                align-items: center;
                gap: 8px;
                padding: 10px 16px;
                margin-bottom: 4px;
                background: #f7f6f3;
                border: 1px solid #191919;
                border-radius: 8px;
                cursor: pointer;
                font-weight: 600;
                font-size: 0.95em;
                color: #191919;
                transition: background 0.15s;
                user-select: none;
            }

            .tree-toggle:hover {
                background: #edece9;
            }

            .tree-toggle .arrow {
                transition: transform 0.2s ease;
                font-size: 0.7em;
                color: #787774;
            }

            .tree-toggle.collapsed .arrow {
                transform: rotate(-90deg);
            }

            .tree-toggle .count {
                font-size: 0.75em;
                color: #787774;
                font-weight: 400;
                margin-left: auto;
            }

            .tree-children {
                overflow: hidden;
            }

            .tree-children.collapsed {
                display: none;
            }

            body.dark-mode {
                background: #191919;
                color: #e9e9e7;
            }

            body.dark-mode .container {
                background: #252525;
                border-color: #383838;
            }

            body.dark-mode header {
                background: #000;
                border-bottom-color: #383838;
            }

            body.dark-mode .stats-panel {
                background: #191919;
                border-bottom-color: #383838;
            }

            body.dark-mode .stat-card {
                background: #252525;
                border-right-color: #383838;
                color: #e9e9e7;
            }

            body.dark-mode .stat-card .value {
                color: #e9e9e7;
            }

            body.dark-mode .controls {
                background: #252525;
                border-bottom-color: #383838;
            }

            body.dark-mode .btn {
                background: #252525;
                color: #e9e9e7;
                border-color: #383838;
            }

            body.dark-mode .btn:hover {
                background: #333;
            }

            body.dark-mode .btn-primary, body.dark-mode .btn.active {
                background: #e9e9e7;
                color: #191919;
                border-color: #e9e9e7;
            }

            body.dark-mode .search-box {
                background: #252525;
                color: #e9e9e7;
                border-color: #383838;
            }

            body.dark-mode .search-box:focus {
                border-color: #e9e9e7;
            }

            body.dark-mode .benchmarks {
                background: #252525;
            }

            body.dark-mode .benchmark-item {
                border-color: #383838;
            }

            body.dark-mode .benchmark-item:hover {
                border-color: #e9e9e7;
            }

            body.dark-mode .benchmark-header {
                background: #191919;
                border-bottom-color: #383838;
            }

            body.dark-mode .benchmark-name {
                color: #e9e9e7;
            }

            body.dark-mode .stat-val {
                color: #e9e9e7;
            }

            body.dark-mode .plot-container {
                background: #252525;
            }

            body.dark-mode .tree-toggle {
                background: #191919;
                border-color: #383838;
                color: #e9e9e7;
            }

            body.dark-mode .tree-toggle:hover {
                background: #2a2a2a;
            }

            body.dark-mode .tree-toggle .count {
                color: #787774;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <header>
                <h1>$group_name</h1>
                <p>Benchmark Dashboard &nbsp;&bull;&nbsp; Commit: <a href="$repo_url/commit/$commit_sha" target="_blank" style="color: #ccc; text-decoration: none;">$commit_short</a></p>
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
                <p>Generated by <a href="$repo_url" target="_blank">BenchmarkExplorer.jl</a></p>
            </footer>
        </div>

        <script>
            const benchmarksData = $benchmarks_json;
            const statsData = $stats_json;
            const repoUrl = '$repo_url';
            const commitBaseUrl = '$commit_base_url';
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

            function toPercentage(values) {
                if (!percentageMode || values.length === 0) return values;
                return values.map((v, i) => {
                    if (i === 0) return 0;
                    const prev = values[i - 1];
                    if (prev === 0) return 0;
                    return ((v / prev) - 1) * 100;
                });
            }

            function renderSinglePlot(name, data, plotId) {
                if (renderedPlots.has(plotId)) return;
                renderedPlots.add(plotId);

                const plotDiv = document.getElementById(plotId);
                if (plotDiv) plotDiv.innerHTML = '';

                const meanTrace = {
                    x: data.mean.x,
                    y: toPercentage(data.mean.y),
                    type: 'scatter',
                    mode: 'lines+markers',
                    name: 'Mean',
                    line: {color: '#191919', width: 2},
                    marker: {size: 6, color: '#191919'},
                    hovertext: data.mean.hovertext,
                    hoverinfo: data.mean.hoverinfo || 'text'
                };

                if (data.mean.error_y && !percentageMode) {
                    meanTrace.error_y = {
                        type: 'data',
                        array: data.mean.error_y.array,
                        visible: true,
                        color: 'rgba(120, 119, 116, 0.5)',
                        thickness: 1.5,
                        width: 4
                    };
                }

                const traces = [
                    meanTrace,
                    {
                        x: data.min.x,
                        y: toPercentage(data.min.y),
                        type: 'scatter',
                        mode: 'lines',
                        name: 'Min',
                        line: {color: '#787774', width: 1.5, dash: 'dash'},
                        visible: 'legendonly',
                        hovertemplate: percentageMode ?
                            'Commit: %{x}<br>Min: %{y:.2f}%<extra></extra>' :
                            'Commit: %{x}<br>Min: %{y:.3f} ms<extra></extra>'
                    },
                    {
                        x: data.median.x,
                        y: toPercentage(data.median.y),
                        type: 'scatter',
                        mode: 'lines',
                        name: 'Median',
                        line: {color: '#aaa', width: 1.5, dash: 'dot'},
                        visible: 'legendonly',
                        hovertemplate: percentageMode ?
                            'Commit: %{x}<br>Median: %{y:.2f}%<extra></extra>' :
                            'Commit: %{x}<br>Median: %{y:.3f} ms<extra></extra>'
                    }
                ];

                const layout = {
                    title: '',
                    height: 350,
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
                    plot_bgcolor: darkMode ? '#252525' : '#ffffff',
                    paper_bgcolor: darkMode ? '#252525' : '#ffffff',
                    font: {
                        color: darkMode ? '#e9e9e7' : '#191919',
                        family: '-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif'
                    },
                    autosize: true
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

                plotDiv.on('plotly_click', function(clickData) {
                    if (!clickData || !clickData.points || clickData.points.length === 0) return;
                    const pt = clickData.points[0];
                    const idx = pt.pointIndex;
                    showDetailPage(name, data, idx);
                });
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

            function buildTree(entries) {
                const tree = {};
                entries.forEach(([name, data]) => {
                    const parts = name.split('/');
                    let node = tree;
                    for (let i = 0; i < parts.length; i++) {
                        const part = parts[i];
                        if (!node[part]) node[part] = {};
                        if (i === parts.length - 1) {
                            node[part].__leaf = { name, data };
                        } else {
                            if (!node[part].__children) node[part].__children = {};
                            node = node[part].__children;
                        }
                    }
                });
                return tree;
            }

            function countLeaves(node) {
                let count = 0;
                for (const key of Object.keys(node)) {
                    if (key === '__leaf' || key === '__children') continue;
                    if (node[key].__leaf) count++;
                    if (node[key].__children) count += countLeaves(node[key].__children);
                }
                return count;
            }

            function renderTreeNode(node, container, depth) {
                const keys = Object.keys(node).filter(k => k !== '__leaf' && k !== '__children').sort();
                for (const key of keys) {
                    const entry = node[key];
                    if (entry.__leaf) {
                        const { name, data } = entry.__leaf;
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
                                    <span>\${key}</span>
                                    \${trendBadge}
                                </div>
                                <div class="benchmark-stats">
                                    <div class="stat">
                                        <span class="stat-key">Latest</span>
                                        <span class="stat-val">\${stats.latest_mean} ms</span>
                                    </div>
                                    <div class="stat">
                                        <span class="stat-key">Commit</span>
                                        <span class="stat-val"><a href="\${commitBaseUrl}/commit/\${stats.latest_commit}" target="_blank" style="color: #667eea; text-decoration: none;">\${stats.latest_commit.substring(0, 7)}</a></span>
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
                        if (plotObserver) {
                            plotObserver.observe(item.querySelector('.plot-container'));
                        }
                    }
                    if (entry.__children) {
                        const leafCount = countLeaves(entry.__children) + (entry.__leaf ? 1 : 0);
                        const treeNode = document.createElement('div');
                        treeNode.className = depth === 0 ? 'tree-node root' : 'tree-node';

                        const toggle = document.createElement('div');
                        toggle.className = 'tree-toggle';
                        toggle.innerHTML = `<span class="arrow">&#9660;</span> \${key} <span class="count">\${leafCount} benchmarks</span>`;
                        toggle.addEventListener('click', function() {
                            this.classList.toggle('collapsed');
                            children.classList.toggle('collapsed');
                        });

                        const children = document.createElement('div');
                        children.className = 'tree-children';

                        renderTreeNode(entry.__children, children, depth + 1);

                        treeNode.appendChild(toggle);
                        treeNode.appendChild(children);
                        container.appendChild(treeNode);
                    }
                }
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

                const tree = buildTree(filtered);
                renderTreeNode(tree, container, 0);
            }

            function calcPercentFromPrev(values) {
                return values.map((v, i) => {
                    if (i === 0) return 0;
                    const prev = values[i - 1];
                    if (prev === 0) return 0;
                    return ((v / prev) - 1) * 100;
                });
            }

            function updatePercentageMode() {
                Object.entries(benchmarksData).forEach(([name, data]) => {
                    const plotId = 'plot-' + name.replace(/[^a-zA-Z0-9]/g, '-');
                    const plotDiv = document.getElementById(plotId);
                    if (!plotDiv || !plotDiv.data) return;

                    const currentVisibility = plotDiv.data.map(trace => trace.visible);

                    const rawMean = data.mean.y_raw || data.mean.y;
                    const rawMin = data.min.y_raw || data.min.y;
                    const rawMedian = data.median.y_raw || data.median.y;

                    const newMeanY = percentageMode ? calcPercentFromPrev(rawMean) : rawMean;
                    const newMinY = percentageMode ? calcPercentFromPrev(rawMin) : rawMin;
                    const newMedianY = percentageMode ? calcPercentFromPrev(rawMedian) : rawMedian;

                    const meanHoverTexts = percentageMode ?
                        data.mean.commit_hashes.map((hash, i) =>
                            \`Commit: \${hash}<br>Change: \${newMeanY[i].toFixed(2)}%<br>Original: \${rawMean[i].toFixed(3)} ms<br>Date: \${formatDate(data.mean.timestamps[i])}\`
                        ) : data.mean.hovertext;

                    const errorUpdate = percentageMode ?
                        {'error_y.visible': false} :
                        (data.mean.error_y ? {'error_y.visible': true} : {});

                    Plotly.restyle(plotDiv, Object.assign({y: [newMeanY], hovertext: [meanHoverTexts]}, errorUpdate), [0]);
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
                        'yaxis.title': percentageMode ? 'Change from prev (%)' : 'Time (ms)',
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
                            'plot_bgcolor': darkMode ? '#252525' : '#ffffff',
                            'paper_bgcolor': darkMode ? '#252525' : '#ffffff',
                            'font.color': darkMode ? '#e9e9e7' : '#191919'
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

                    for (const runInfo of group.runs) {
                        const runResponse = await fetch('benchmarks/' + runInfo.url);
                        const runData = await runResponse.json();

                        for (const [benchName, data] of Object.entries(runData.benchmarks)) {
                            if (!benchmarksData[benchName]) continue;

                            const commitHash = runData.metadata.commit_hash || 'unknown';
                            const commitShort = commitHash.substring(0, 7);

                            if (benchmarksData[benchName].mean.commit_hashes.includes(commitHash)) {
                                continue;
                            }

                            benchmarksData[benchName].mean.x.push(commitShort);
                            benchmarksData[benchName].mean.y.push(data.mean_time_ns / 1e6);
                            benchmarksData[benchName].mean.timestamps.push(runData.metadata.timestamp);
                            benchmarksData[benchName].mean.commit_hashes.push(commitHash);

                            benchmarksData[benchName].min.x.push(commitShort);
                            benchmarksData[benchName].min.y.push(data.min_time_ns / 1e6);

                            benchmarksData[benchName].median.x.push(commitShort);
                            benchmarksData[benchName].median.y.push(data.median_time_ns / 1e6);

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
                            benchmarksData[benchName].stats.num_runs++;
                        }
                    }

                    const panel = document.getElementById('stats-panel');
                    const totalRunsCard = panel.children[1];
                    if (totalRunsCard) {
                        totalRunsCard.querySelector('.value').textContent = group.total_runs;
                    }

                    fullHistoryLoaded = true;
                    this.textContent = '✅ Full History Loaded';
                    renderBenchmarks(document.getElementById('search').value);

                } catch (error) {
                    console.error('Failed to load full history:', error);
                    this.textContent = '❌ Load Failed';
                    this.disabled = false;
                }
            });
            """ : "")

            function showDetailPage(benchName, data, idx) {
                const rawMean = data.mean.y_raw || data.mean.y;
                const rawMin = data.min.y_raw || data.min.y;
                const rawMedian = data.median.y_raw || data.median.y;

                const commit = data.mean.commit_hashes[idx] || 'unknown';
                const commitShort = commit.substring(0, 7);
                const timestamp = data.mean.timestamps[idx] || '';
                const meanVal = rawMean[idx];
                const minVal = rawMin[idx];
                const medianVal = rawMedian[idx];
                const memory = data.stats.latest_memory;
                const allocs = data.stats.latest_allocs;
                const errVal = data.mean.error_y ? data.mean.error_y.array[idx] : 0;

                let changeHtml = '';
                if (idx > 0) {
                    const prevMean = rawMean[idx - 1];
                    if (prevMean > 0) {
                        const change = ((meanVal / prevMean) - 1) * 100;
                        const changeColor = change < -1 ? '#27ae60' : (change > 1 ? '#e74c3c' : '#6c757d');
                        const sign = change > 0 ? '+' : '';
                        changeHtml = '<div class="d-card wide"><div class="d-label">Change from previous commit</div><div class="d-value" style="color:' + changeColor + ';font-size:2em">' + sign + change.toFixed(2) + '%</div></div>';
                    }
                }

                const commitLink = commit !== 'unknown' ? '<a href="' + commitBaseUrl + '/commit/' + commit + '" target="_blank" style="color:#667eea;text-decoration:none">' + commit + '</a>' : commit;

                const html = '<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>' + benchName + ' - ' + commitShort + '</title><style>' +
                    '*{margin:0;padding:0;box-sizing:border-box}' +
                    'body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);min-height:100vh;padding:20px}' +
                    '.container{max-width:900px;margin:0 auto;background:white;border-radius:20px;box-shadow:0 20px 60px rgba(0,0,0,0.3);overflow:hidden}' +
                    'header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;padding:30px 40px}' +
                    'header h1{font-size:1.6em;margin-bottom:8px;word-break:break-all}' +
                    'header p{opacity:0.9;font-size:1em}' +
                    '.body{padding:30px 40px}' +
                    '.d-grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px;margin-bottom:24px}' +
                    '.d-card{background:#f8f9fa;padding:20px;border-radius:12px;text-align:center}' +
                    '.d-card.wide{grid-column:1/-1}' +
                    '.d-label{font-size:0.8em;color:#6c757d;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:8px}' +
                    '.d-value{font-size:1.5em;font-weight:bold;color:#2c3e50}' +
                    '.d-value.blue{color:#667eea}' +
                    '.d-value.green{color:#27ae60}' +
                    '.info-table{width:100%;border-collapse:collapse;margin-top:20px}' +
                    '.info-table th,.info-table td{padding:12px 16px;text-align:left;border-bottom:1px solid #e9ecef}' +
                    '.info-table th{color:#6c757d;font-size:0.85em;text-transform:uppercase;letter-spacing:0.5px;width:140px}' +
                    '.info-table td{color:#2c3e50;font-weight:500}' +
                    '.btn-back{display:inline-block;margin-top:24px;padding:10px 24px;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;text-decoration:none;border-radius:8px;font-weight:600;border:none;cursor:pointer;font-size:1em}' +
                    '</style></head><body><div class="container"><header><h1>' + benchName + '</h1><p>Commit ' + commitShort + ' &bull; ' + formatDate(timestamp) + '</p></header><div class="body">' +
                    changeHtml +
                    '<div class="d-grid">' +
                    '<div class="d-card"><div class="d-label">Mean</div><div class="d-value blue">' + meanVal.toFixed(3) + ' ms</div></div>' +
                    '<div class="d-card"><div class="d-label">Median</div><div class="d-value">' + medianVal.toFixed(3) + ' ms</div></div>' +
                    '<div class="d-card"><div class="d-label">Min</div><div class="d-value green">' + minVal.toFixed(3) + ' ms</div></div>' +
                    (errVal > 0 ? '<div class="d-card"><div class="d-label">Std Dev</div><div class="d-value">' + errVal.toFixed(3) + ' ms</div></div>' : '') +
                    '<div class="d-card"><div class="d-label">Memory</div><div class="d-value">' + formatBytes(memory) + '</div></div>' +
                    '<div class="d-card"><div class="d-label">Allocations</div><div class="d-value">' + allocs + '</div></div>' +
                    '</div>' +
                    '<table class="info-table">' +
                    '<tr><th>Commit</th><td>' + commitLink + '</td></tr>' +
                    '<tr><th>Date</th><td>' + formatDate(timestamp) + '</td></tr>' +
                    '<tr><th>Mean Time</th><td>' + meanVal.toFixed(6) + ' ms (' + (meanVal * 1e6).toFixed(0) + ' ns)</td></tr>' +
                    '<tr><th>Median Time</th><td>' + medianVal.toFixed(6) + ' ms (' + (medianVal * 1e6).toFixed(0) + ' ns)</td></tr>' +
                    '<tr><th>Min Time</th><td>' + minVal.toFixed(6) + ' ms (' + (minVal * 1e6).toFixed(0) + ' ns)</td></tr>' +
                    (errVal > 0 ? '<tr><th>Std Dev</th><td>' + errVal.toFixed(6) + ' ms</td></tr>' : '') +
                    '<tr><th>Memory</th><td>' + formatBytes(memory) + ' (' + memory + ' bytes)</td></tr>' +
                    '<tr><th>Allocations</th><td>' + allocs + '</td></tr>' +
                    '</table>' +
                    '<button class="btn-back" onclick="window.close()">Close</button>' +
                    '</div></div></body></html>';

                const w = window.open('', '_blank');
                if (w) {
                    w.document.write(html);
                    w.document.close();
                }
            }

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
    commit_base_url = length(ARGS) >= 6 ? ARGS[6] : repo_url

    generate_static_page_plotly(data_dir, output_file, group_name, repo_url, commit_sha, commit_base_url)
end
