using Pkg
Pkg.activate(@__DIR__)

using Bonito
using WGLMakie
using Dates
using Printf
using JSON

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
                    run_time = DateTime(latest_run["timestamp"])
                    if isnothing(last_run_time) || run_time > last_run_time
                        last_run_time = run_time
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

function create_benchmark_plot(runs, show_mean, show_min, show_median, show_percentage, dark_mode)
    run_numbers = sort(parse.(Int, keys(runs)))
    isempty(run_numbers) && return Figure()

    mean_times = Float64[]
    min_times = Float64[]
    median_times = Float64[]

    for rn in run_numbers
        data = runs[string(rn)]
        push!(mean_times, get(data, "mean_time_ns", 0) / 1e6)
        push!(min_times, get(data, "min_time_ns", 0) / 1e6)
        push!(median_times, get(data, "median_time_ns", 0) / 1e6)
    end

    x = collect(1:length(run_numbers))

    mean_data = @lift begin
        if $show_percentage && length(mean_times) > 0 && mean_times[1] > 0
            [(t / mean_times[1] - 1.0) * 100.0 for t in mean_times]
        else
            mean_times
        end
    end

    min_data = @lift begin
        if $show_percentage && length(min_times) > 0 && min_times[1] > 0
            [(t / min_times[1] - 1.0) * 100.0 for t in min_times]
        else
            min_times
        end
    end

    median_data = @lift begin
        if $show_percentage && length(median_times) > 0 && median_times[1] > 0
            [(t / median_times[1] - 1.0) * 100.0 for t in median_times]
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

    lines!(ax, x, mean_data, color=:steelblue, linewidth=2, visible=show_mean, label="Mean")
    scatter!(ax, x, mean_data, color=:steelblue, markersize=8, visible=show_mean)

    lines!(ax, x, min_data, color=:green, linewidth=2, visible=show_min, label="Min")
    scatter!(ax, x, min_data, color=:green, markersize=6, visible=show_min)

    lines!(ax, x, median_data, color=:orange, linewidth=2, visible=show_median, label="Median")
    scatter!(ax, x, median_data, color=:orange, markersize=6, visible=show_median)

    hlines!(ax, [0.0], color=:gray, linestyle=:dash, linewidth=1, visible=show_percentage)

    axislegend(ax, position=:lt, backgroundcolor=bg_color)

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
        search_filter = Observable("")
        trend_filter = Observable("all")

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
            .search-box { flex: 1; min-width: 250px; padding: 12px 20px; border: 2px solid #e9ecef; border-radius: 8px; font-size: 1em; }
            .search-box:focus { outline: none; border-color: #667eea; }
            .trend-select { padding: 12px 15px; border: 2px solid #e9ecef; border-radius: 8px; font-size: 1em; background: white; }
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
            .dark .search-box, .dark .trend-select { background: #2c3e50; color: #ecf0f1; border-color: #4a5568; }
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

                fig = create_benchmark_plot(runs, show_mean, show_min, show_median, show_percentage, dark_mode)

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
                    class="benchmark-card",
                    dataPath=benchmark_path,
                    dataTrend=trend
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

        header = DOM.div(
            DOM.h1("📊 BenchmarkExplorer"),
            DOM.p("Interactive Benchmark Dashboard"),
            class="header"
        )

        footer = DOM.div(
            DOM.p("Generated by ", DOM.a("BenchmarkExplorer.jl", href=REPO_URL, target="_blank"), " • Powered by Bonito.jl + WGLMakie.jl"),
            class="footer"
        )

        DOM.div(
            css,
            DOM.div(
                DOM.div(
                    header,
                    stats_panel,
                    controls,
                    DOM.div(benchmark_cards..., class="benchmarks"),
                    footer,
                    class="container"
                ),
                class=dark_class
            )
        )
    end

    server = Bonito.Server(app, "0.0.0.0", port)
    return server
end

if abspath(PROGRAM_FILE) == @__FILE__
    port = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 8000
    data_dir = length(ARGS) >= 2 ? ARGS[2] : "data"

    server = start_dashboard(data_dir; port=port)
    wait(server)
end
