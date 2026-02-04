using Pkg
Pkg.activate(@__DIR__)

using Bonito
using WGLMakie
using Dates
using Printf
using JSON
using URIs
using HTTP

include("src/HistoryManager.jl")
using .HistoryManager

const REPO_URL = "https://github.com/hpsc-lab/BenchmarkExplorer.jl"

function format_time_short(ns)
    if ns < 1e3
        return @sprintf("%.0f ns", ns)
    elseif ns < 1e6
        return @sprintf("%.1f μs", ns / 1e3)
    elseif ns < 1e9
        return @sprintf("%.2f ms", ns / 1e6)
    else
        return @sprintf("%.2f s", ns / 1e9)
    end
end

function format_memory(bytes)
    if bytes < 1024
        return "$bytes B"
    elseif bytes < 1024^2
        return @sprintf("%.1f KB", bytes / 1024)
    elseif bytes < 1024^3
        return @sprintf("%.1f MB", bytes / 1024^2)
    else
        return @sprintf("%.2f GB", bytes / 1024^3)
    end
end

function format_time_ago(dt)
    isnothing(dt) && return "Unknown"
    diff = now() - dt
    hours = Dates.value(diff) / (1000 * 3600)
    if hours < 1
        return "$(round(Int, hours * 60)) min ago"
    elseif hours < 24
        return "$(round(Int, hours)) hours ago"
    else
        return "$(round(Int, hours / 24)) days ago"
    end
end

function calculate_stats(histories)
    total_benchmarks = 0
    total_runs = 0
    last_run_time = nothing
    fastest_bench = ("", Inf)
    slowest_bench = ("", 0.0)

    for (group_name, history) in histories
        for (bench_path, runs) in history
            total_benchmarks += 1
            run_numbers = sort(parse.(Int, keys(runs)))
            total_runs += length(run_numbers)

            if !isempty(run_numbers)
                latest_run = runs[string(run_numbers[end])]

                if haskey(latest_run, "timestamp")
                    try
                        run_time = DateTime(split(latest_run["timestamp"], ".")[1])
                        if isnothing(last_run_time) || run_time > last_run_time
                            last_run_time = run_time
                        end
                    catch
                    end
                end

                mean_time = get(latest_run, "mean_time_ns", Inf)
                if mean_time < fastest_bench[2]
                    fastest_bench = (bench_path, mean_time)
                end
                if mean_time > slowest_bench[2]
                    slowest_bench = (bench_path, mean_time)
                end
            end
        end
    end

    return (
        total_benchmarks = total_benchmarks,
        total_runs = total_runs,
        last_run = last_run_time,
        fastest = fastest_bench,
        slowest = slowest_bench
    )
end

function calculate_trend(runs)
    run_numbers = sort(parse.(Int, keys(runs)))
    length(run_numbers) < 2 && return ("stable", 0.0)

    latest = runs[string(run_numbers[end])]
    baseline = runs[string(run_numbers[1])]

    latest_mean = get(latest, "mean_time_ns", 0) / 1e6
    baseline_mean = get(baseline, "mean_time_ns", 1) / 1e6

    baseline_mean == 0 && return ("stable", 0.0)

    pct = round(((latest_mean / baseline_mean) - 1) * 100, digits=1)
    trend = pct < -5 ? "faster" : (pct > 5 ? "slower" : "stable")

    return (trend, pct)
end

function create_benchmark_plot(runs, group_name, benchmark_path, port, show_mean, show_min, show_median, show_percentage, dark_mode)
    run_numbers = sort(parse.(Int, keys(runs)))
    isempty(run_numbers) && return Figure()

    mean_times = Float64[]
    min_times = Float64[]
    median_times = Float64[]
    commits = String[]
    timestamps = String[]

    for rn in run_numbers
        data = runs[string(rn)]
        push!(mean_times, get(data, "mean_time_ns", 0) / 1e6)
        push!(min_times, get(data, "min_time_ns", 0) / 1e6)
        push!(median_times, get(data, "median_time_ns", 0) / 1e6)
        push!(commits, get(data, "commit_hash", "unknown")[1:min(7, length(get(data, "commit_hash", "unknown")))])
        push!(timestamps, get(data, "timestamp", ""))
    end

    function calc_pct_from_prev(values)
        result = zeros(length(values))
        for i in 2:length(values)
            if values[i-1] > 0
                result[i] = (values[i] / values[i-1] - 1.0) * 100.0
            end
        end
        return result
    end

    mean_data = @lift begin
        if $show_percentage && length(mean_times) > 0
            calc_pct_from_prev(mean_times)
        else
            mean_times
        end
    end

    min_data = @lift begin
        if $show_percentage && length(min_times) > 0
            calc_pct_from_prev(min_times)
        else
            min_times
        end
    end

    median_data = @lift begin
        if $show_percentage && length(median_times) > 0
            calc_pct_from_prev(median_times)
        else
            median_times
        end
    end

    ylabel = @lift $show_percentage ? "Change (%)" : "Time (ms)"
    bg_color = @lift $dark_mode ? RGBf(0.17, 0.24, 0.31) : :white
    text_color = @lift $dark_mode ? :white : :black

    fig = Figure(size=(600, 300), backgroundcolor=bg_color)
    ax = Axis(fig[1, 1],
        xlabel="Run #",
        ylabel=ylabel,
        backgroundcolor=bg_color,
        xlabelcolor=text_color,
        ylabelcolor=text_color,
        xticklabelcolor=text_color,
        yticklabelcolor=text_color)

    lines!(ax, run_numbers, mean_data, color=:steelblue, linewidth=2, visible=show_mean, label="Mean")
    scatter!(ax, run_numbers, mean_data, color=:steelblue, markersize=10, visible=show_mean,
        inspector_label = (self, i, p) -> begin
            idx = findfirst(==(round(Int, p[1])), run_numbers)
            if !isnothing(idx) && idx <= length(mean_times)
                run_data = runs[string(run_numbers[idx])]
                """
                Run #$(run_numbers[idx])
                Mean: $(round(mean_times[idx], digits=3)) ms
                Min: $(round(min_times[idx], digits=3)) ms
                Median: $(round(median_times[idx], digits=3)) ms
                Memory: $(format_memory(get(run_data, "memory_bytes", 0)))
                Allocs: $(get(run_data, "allocs", 0))
                Commit: $(commits[idx])
                Click to open details
                """
            else
                ""
            end
        end)

    lines!(ax, run_numbers, min_data, color=:green, linewidth=2, visible=show_min, label="Min")
    scatter!(ax, run_numbers, min_data, color=:green, markersize=8, visible=show_min,
        inspector_label = (self, i, p) -> begin
            idx = findfirst(==(round(Int, p[1])), run_numbers)
            if !isnothing(idx) && idx <= length(min_times)
                "Run #$(run_numbers[idx])\nMin: $(round(min_times[idx], digits=3)) ms\nClick to open details"
            else
                ""
            end
        end)

    lines!(ax, run_numbers, median_data, color=:orange, linewidth=2, visible=show_median, label="Median")
    scatter!(ax, run_numbers, median_data, color=:orange, markersize=8, visible=show_median,
        inspector_label = (self, i, p) -> begin
            idx = findfirst(==(round(Int, p[1])), run_numbers)
            if !isnothing(idx) && idx <= length(median_times)
                "Run #$(run_numbers[idx])\nMedian: $(round(median_times[idx], digits=3)) ms\nClick to open details"
            else
                ""
            end
        end)

    hlines!(ax, [0.0], color=:gray, linestyle=:dash, linewidth=1, visible=show_percentage)

    axislegend(ax, position=:lt, backgroundcolor=bg_color)
    DataInspector(fig)

    on(events(fig).mousebutton) do event
        if event.button == Mouse.left && event.action == Mouse.press
            plt = mouseposition(ax.scene)

            closest_idx = 0
            min_dist = Inf

            for (i, rn) in enumerate(run_numbers)
                if show_mean[]
                    dx = plt[1] - rn
                    dy = plt[2] - mean_data[][i]
                    dist = sqrt(dx^2 + dy^2)
                    if dist < min_dist && dist < 2.0
                        min_dist = dist
                        closest_idx = i
                    end
                end

                if show_min[]
                    dx = plt[1] - rn
                    dy = plt[2] - min_data[][i]
                    dist = sqrt(dx^2 + dy^2)
                    if dist < min_dist && dist < 2.0
                        min_dist = dist
                        closest_idx = i
                    end
                end

                if show_median[]
                    dx = plt[1] - rn
                    dy = plt[2] - median_data[][i]
                    dist = sqrt(dx^2 + dy^2)
                    if dist < min_dist && dist < 2.0
                        min_dist = dist
                        closest_idx = i
                    end
                end
            end

            if closest_idx > 0
                run_num = run_numbers[closest_idx]
                encoded_path = URIs.escapeuri(benchmark_path)
                detail_url = "http://localhost:$port/detail/$group_name/$encoded_path/$run_num"

                try
                    if Sys.islinux()
                        run(`xdg-open $detail_url`, wait=false)
                    elseif Sys.isapple()
                        run(`open $detail_url`, wait=false)
                    elseif Sys.iswindows()
                        run(`cmd /c start $detail_url`, wait=false)
                    end
                catch
                end
            end
        end
    end

    return fig
end

function start_dashboard(data_dir="data"; port=8000)
    all_groups = load_history(data_dir)
    histories = Dict{String, Any}()

    for (group, history) in all_groups
        histories[group] = history
    end

    if isempty(histories)
        error("No benchmark data found in $data_dir")
    end

    stats = calculate_stats(histories)

    app = App() do session
        show_mean = Observable(true)
        show_min = Observable(false)
        show_median = Observable(false)
        show_percentage = Observable(false)
        dark_mode = Observable(false)

        css = DOM.style("""
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
            .dashboard { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; padding: 20px; }
            .container { max-width: 1600px; margin: 0 auto; background: white; border-radius: 20px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); overflow: hidden; }
            .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; text-align: center; }
            .header h1 { font-size: 2.5em; margin-bottom: 10px; }
            .header p { font-size: 1.1em; opacity: 0.9; }
            .stats-panel { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 20px; padding: 30px; background: #f8f9fa; }
            .stat-card { background: white; padding: 20px; border-radius: 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); text-align: center; }
            .stat-card .value { font-size: 2em; font-weight: bold; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
            .stat-card .label { color: #6c757d; font-size: 0.85em; text-transform: uppercase; }
            .controls { padding: 20px 30px; background: white; border-bottom: 1px solid #e9ecef; display: flex; gap: 15px; flex-wrap: wrap; align-items: center; }
            .control-group { display: flex; align-items: center; gap: 8px; background: #f8f9fa; padding: 10px 15px; border-radius: 8px; }
            .control-group label { cursor: pointer; font-weight: 500; color: #495057; }
            .benchmarks { padding: 30px; }
            .benchmark-card { background: white; border: 2px solid #e9ecef; border-radius: 12px; margin-bottom: 25px; overflow: hidden; transition: all 0.3s; }
            .benchmark-card:hover { border-color: #667eea; box-shadow: 0 4px 12px rgba(102, 126, 234, 0.15); }
            .benchmark-header { background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%); padding: 20px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 15px; }
            .benchmark-name { font-size: 1.2em; font-weight: bold; color: #2c3e50; display: flex; align-items: center; gap: 10px; }
            .trend-badge { padding: 5px 12px; border-radius: 20px; font-size: 0.8em; font-weight: bold; }
            .trend-faster { background: #d4edda; color: #155724; }
            .trend-slower { background: #f8d7da; color: #721c24; }
            .trend-stable { background: #d1ecf1; color: #0c5460; }
            .benchmark-stats { display: flex; gap: 25px; flex-wrap: wrap; }
            .stat { text-align: center; }
            .stat-key { display: block; font-size: 0.75em; color: #6c757d; text-transform: uppercase; margin-bottom: 3px; }
            .stat-val { font-weight: bold; color: #2c3e50; }
            .stat-val a { color: #667eea; text-decoration: none; }
            .stat-val a:hover { text-decoration: underline; }
            .plot-container { padding: 15px; }
            .footer { background: #2c3e50; color: white; text-align: center; padding: 20px; }
            .footer a { color: #667eea; }
            .dark .container { background: #2c3e50; }
            .dark .stats-panel { background: #34495e; }
            .dark .stat-card { background: #2c3e50; }
            .dark .controls { background: #34495e; border-color: #4a5568; }
            .dark .control-group { background: #2c3e50; }
            .dark .control-group label { color: #ecf0f1; }
            .dark .benchmarks { background: #2c3e50; }
            .dark .benchmark-card { background: #34495e; border-color: #4a5568; }
            .dark .benchmark-header { background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%); }
            .dark .benchmark-name { color: #ecf0f1; }
            .dark .stat-val { color: #ecf0f1; }
        """)

        stats_panel = DOM.div(
            DOM.div(DOM.div(string(stats.total_benchmarks), class="value"), DOM.div("Benchmarks", class="label"), class="stat-card"),
            DOM.div(DOM.div(string(stats.total_runs), class="value"), DOM.div("Total Runs", class="label"), class="stat-card"),
            DOM.div(DOM.div(format_time_short(stats.fastest[2]), class="value", style="-webkit-text-fill-color: #27ae60;"), DOM.div("Fastest", class="label"), class="stat-card"),
            DOM.div(DOM.div(format_time_short(stats.slowest[2]), class="value", style="-webkit-text-fill-color: #e74c3c;"), DOM.div("Slowest", class="label"), class="stat-card"),
            DOM.div(DOM.div(format_time_ago(stats.last_run), class="value", style="font-size: 1.2em;"), DOM.div("Last Updated", class="label"), class="stat-card"),
            class="stats-panel"
        )

        mean_cb = Bonito.Checkbox(show_mean, Dict{Symbol,Any}())
        min_cb = Bonito.Checkbox(show_min, Dict{Symbol,Any}())
        median_cb = Bonito.Checkbox(show_median, Dict{Symbol,Any}())
        pct_cb = Bonito.Checkbox(show_percentage, Dict{Symbol,Any}())
        dark_cb = Bonito.Checkbox(dark_mode, Dict{Symbol,Any}())

        benchmark_cards = []

        for (group_name, history) in histories
            for benchmark_path in sort(collect(keys(history)))
                runs = history[benchmark_path]
                run_numbers = sort(parse.(Int, keys(runs)))
                isempty(run_numbers) && continue

                latest = runs[string(run_numbers[end])]
                trend, pct = calculate_trend(runs)

                latest_mean = round(get(latest, "mean_time_ns", 0) / 1e6, digits=3)
                commit = get(latest, "commit_hash", "unknown")
                commit_short = length(commit) >= 7 ? commit[1:7] : commit
                memory = format_memory(get(latest, "memory_bytes", 0))
                allocs = get(latest, "allocs", 0)
                num_runs = length(run_numbers)

                trend_badge = if num_runs > 1
                    arrow = trend == "faster" ? "↓" : (trend == "slower" ? "↑" : "→")
                    sign = pct > 0 ? "+" : ""
                    DOM.span("$arrow $(sign)$(pct)%", class="trend-badge trend-$trend")
                else
                    DOM.span()
                end

                fig = create_benchmark_plot(runs, group_name, benchmark_path, port, show_mean, show_min, show_median, show_percentage, dark_mode)

                card = DOM.div(
                    DOM.div(
                        DOM.div(
                            DOM.span(benchmark_path),
                            trend_badge,
                            class="benchmark-name"
                        ),
                        DOM.div(
                            DOM.div(DOM.span("Latest", class="stat-key"), DOM.span("$(latest_mean) ms", class="stat-val"), class="stat"),
                            DOM.div(DOM.span("Commit", class="stat-key"), DOM.span(DOM.a(commit_short, href="$(REPO_URL)/commit/$commit", target="_blank"), class="stat-val"), class="stat"),
                            DOM.div(DOM.span("Memory", class="stat-key"), DOM.span(memory, class="stat-val"), class="stat"),
                            DOM.div(DOM.span("Allocs", class="stat-key"), DOM.span(string(allocs), class="stat-val"), class="stat"),
                            DOM.div(DOM.span("Runs", class="stat-key"), DOM.span(string(num_runs), class="stat-val"), class="stat"),
                            class="benchmark-stats"
                        ),
                        class="benchmark-header"
                    ),
                    DOM.div(fig, class="plot-container"),
                    class="benchmark-card"
                )

                push!(benchmark_cards, card)
            end
        end

        csv_data = JSON.json(histories)
        export_js = Bonito.JSCode("""
            (e) => {
                const data = $csv_data;
                let csv = 'Group,Benchmark,Run,Timestamp,Mean (ms),Min (ms),Median (ms),Memory,Allocs\\n';
                for (const [group, benchmarks] of Object.entries(data)) {
                    for (const [bench, runs] of Object.entries(benchmarks)) {
                        const runNums = Object.keys(runs).sort((a,b) => parseInt(a) - parseInt(b));
                        for (const rn of runNums) {
                            const r = runs[rn];
                            csv += `"\${group}","\${bench}",\${rn},"\${r.timestamp || ''}",\${((r.mean_time_ns||0)/1e6).toFixed(3)},\${((r.min_time_ns||0)/1e6).toFixed(3)},\${((r.median_time_ns||0)/1e6).toFixed(3)},\${r.memory_bytes||0},\${r.allocs||0}\\n`;
                        }
                    }
                }
                const blob = new Blob([csv], {type: 'text/csv'});
                const url = window.URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = 'benchmarks.csv';
                a.click();
            }
        """)

        dark_class = map(dm -> dm ? "dashboard dark" : "dashboard", dark_mode)

        controls = DOM.div(
            DOM.div(mean_cb, DOM.label("Mean", style="color: #3498db;"), class="control-group"),
            DOM.div(min_cb, DOM.label("Min", style="color: #27ae60;"), class="control-group"),
            DOM.div(median_cb, DOM.label("Median", style="color: #e67e22;"), class="control-group"),
            DOM.div(pct_cb, DOM.label("% Change"), class="control-group"),
            DOM.div(dark_cb, DOM.label("🌙 Dark"), class="control-group"),
            DOM.button("📥 Export CSV", onclick=export_js, style="padding: 10px 20px; background: #48bb78; color: white; border: none; border-radius: 8px; cursor: pointer; font-weight: 600;"),
            class="controls"
        )

        DOM.div(
            css,
            DOM.div(
                DOM.div(
                    DOM.div(DOM.h1("📊 BenchmarkExplorer"), DOM.p("Interactive Dashboard • Click points for details"), class="header"),
                    stats_panel,
                    controls,
                    DOM.div(benchmark_cards..., class="benchmarks"),
                    DOM.div(DOM.p("Generated by ", DOM.a("BenchmarkExplorer.jl", href=REPO_URL, target="_blank"), " • Powered by Bonito.jl + WGLMakie.jl"), class="footer"),
                    class="container"
                ),
                class=dark_class
            )
        )
    end

    server = Bonito.Server(app, "0.0.0.0", port)

    Bonito.route!(server, r"/detail/.*" => function(context)
        path = context.request.target
        parts = split(path[9:end], "/")

        if length(parts) >= 3
            group_name = URIs.unescapeuri(parts[1])
            run_number_str = parts[end]
            benchmark_path = URIs.unescapeuri(join(parts[2:end-1], "/"))

            try
                run_number = parse(Int, run_number_str)

                if haskey(histories, group_name) && haskey(histories[group_name], benchmark_path)
                    runs = histories[group_name][benchmark_path]

                    if haskey(runs, string(run_number))
                        data = runs[string(run_number)]

                        mean_ms = get(data, "mean_time_ns", 0) / 1e6
                        min_ms = get(data, "min_time_ns", 0) / 1e6
                        median_ms = get(data, "median_time_ns", 0) / 1e6
                        max_ms = get(data, "max_time_ns", 0) / 1e6
                        memory_mb = get(data, "memory_bytes", 0) / (1024 * 1024)
                        commit = get(data, "commit_hash", "unknown")

                        detail_html = """
                        <!DOCTYPE html>
                        <html>
                        <head>
                            <title>Run #$run_number - $benchmark_path</title>
                            <meta charset="utf-8">
                            <style>
                                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; padding: 30px; background: #f8f9fa; margin: 0; }
                                .container { max-width: 900px; margin: auto; background: white; padding: 40px; border-radius: 16px; box-shadow: 0 4px 20px rgba(0,0,0,0.1); }
                                h1 { color: #2c3e50; margin-bottom: 5px; font-size: 1.8em; }
                                .subtitle { color: #7f8c8d; margin-bottom: 30px; }
                                h2 { color: #2c3e50; margin-top: 30px; border-bottom: 2px solid #667eea; padding-bottom: 10px; font-size: 1.3em; }
                                .stats-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin: 20px 0; }
                                .stat-box { background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%); padding: 20px; border-radius: 12px; text-align: center; }
                                .stat-label { font-weight: 600; font-size: 0.8em; color: #6c757d; text-transform: uppercase; margin-bottom: 8px; }
                                .stat-value { font-size: 1.8em; font-weight: bold; }
                                .blue { color: #3498db; }
                                .orange { color: #e67e22; }
                                .green { color: #27ae60; }
                                .red { color: #e74c3c; }
                                .purple { color: #9b59b6; }
                                .teal { color: #16a085; }
                                code { background: #e9ecef; padding: 4px 10px; border-radius: 4px; font-family: 'SF Mono', Monaco, monospace; }
                                table { width: 100%; border-collapse: collapse; margin: 20px 0; }
                                td { padding: 12px; border-bottom: 1px solid #e9ecef; }
                                td:first-child { font-weight: 600; width: 150px; color: #6c757d; }
                                .btn { display: inline-block; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border: none; padding: 12px 24px; border-radius: 8px; cursor: pointer; font-size: 14px; font-weight: 600; text-decoration: none; margin-right: 10px; }
                                .btn:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4); }
                                .btn-secondary { background: #6c757d; }
                                pre { background: #2c3e50; color: #ecf0f1; padding: 20px; border-radius: 8px; overflow-x: auto; font-size: 0.85em; }
                                @media (max-width: 768px) { .stats-grid { grid-template-columns: repeat(2, 1fr); } }
                            </style>
                        </head>
                        <body>
                            <div class="container">
                                <h1>📊 Benchmark Details</h1>
                                <div class="subtitle">
                                    <strong>$benchmark_path</strong> • Run #$run_number •
                                    <a href="$REPO_URL/commit/$commit" target="_blank" style="color: #667eea;">$commit</a>
                                </div>

                                <h2>⏱️ Timing Statistics</h2>
                                <div class="stats-grid">
                                    <div class="stat-box">
                                        <div class="stat-label">Mean</div>
                                        <div class="stat-value blue">$(@sprintf("%.3f", mean_ms)) ms</div>
                                    </div>
                                    <div class="stat-box">
                                        <div class="stat-label">Median</div>
                                        <div class="stat-value orange">$(@sprintf("%.3f", median_ms)) ms</div>
                                    </div>
                                    <div class="stat-box">
                                        <div class="stat-label">Min</div>
                                        <div class="stat-value green">$(@sprintf("%.3f", min_ms)) ms</div>
                                    </div>
                                    <div class="stat-box">
                                        <div class="stat-label">Max</div>
                                        <div class="stat-value red">$(@sprintf("%.3f", max_ms)) ms</div>
                                    </div>
                                </div>

                                <h2>💾 Memory</h2>
                                <div class="stats-grid" style="grid-template-columns: repeat(2, 1fr);">
                                    <div class="stat-box">
                                        <div class="stat-label">Memory Used</div>
                                        <div class="stat-value purple">$(@sprintf("%.2f", memory_mb)) MB</div>
                                    </div>
                                    <div class="stat-box">
                                        <div class="stat-label">Allocations</div>
                                        <div class="stat-value teal">$(get(data, "allocs", 0))</div>
                                    </div>
                                </div>

                                <h2>📋 Metadata</h2>
                                <table>
                                    <tr><td>Timestamp</td><td>$(get(data, "timestamp", "unknown"))</td></tr>
                                    <tr><td>Samples</td><td>$(get(data, "samples", "unknown"))</td></tr>
                                    <tr><td>Julia Version</td><td>$(get(data, "julia_version", "unknown"))</td></tr>
                                    <tr><td>Group</td><td>$group_name</td></tr>
                                </table>

                                <h2>📄 Raw Data</h2>
                                <pre>$(JSON.json(data, 2))</pre>

                                <br>
                                <button class="btn" onclick="window.close()">Close</button>
                                <a class="btn btn-secondary" href="/">Back to Dashboard</a>
                            </div>
                        </body>
                        </html>
                        """

                        return HTTP.Response(200, ["Content-Type" => "text/html"], detail_html)
                    end
                end

                return HTTP.Response(404, ["Content-Type" => "text/html"], "<h1>404 - Not Found</h1>")
            catch e
                return HTTP.Response(500, ["Content-Type" => "text/html"], "<h1>500 - Error: $e</h1>")
            end
        end

        return HTTP.Response(404, ["Content-Type" => "text/html"], "<h1>404 - Not Found</h1>")
    end)

index.html:415 
    return server
end

if abspath(PROGRAM_FILE) == @__FILE__
    port = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 8000
    data_dir = length(ARGS) >= 2 ? ARGS[2] : "data"

    server = start_dashboard(data_dir; port=port)
    wait(server)
end
