using Pkg
Pkg.activate(@__DIR__)

using Bonito
using WGLMakie
using Dates
using Printf
using JSON

include("src/BenchmarkUI.jl")
using .BenchmarkUI

const REPO_URL = "https://github.com/hpsc-lab/BenchmarkExplorer.jl"

function format_date_nice(dt::DateTime)
    Dates.format(dt, "d u yyyy, HH:MM")
end

function format_date_nice(iso_str::String)
    try
        dt = DateTime(split(iso_str, ".")[1])
        format_date_nice(dt)
    catch
        iso_str
    end
end

function calculate_trend(history, benchmark_path)
    runs = history[benchmark_path]
    run_numbers = sort([parse(Int, k) for k in keys(runs)])

    length(run_numbers) < 2 && return ("stable", 0.0)

    latest = runs[string(run_numbers[end])]
    baseline = runs[string(run_numbers[1])]

    latest_mean = get(latest, "mean_time_ns", 0) / 1e6
    baseline_mean = get(baseline, "mean_time_ns", 1) / 1e6

    baseline_mean == 0 && return ("stable", 0.0)

    percent_change = round(((latest_mean / baseline_mean) - 1) * 100, digits=2)

    trend = if percent_change < -5
        "faster"
    elseif percent_change > 5
        "slower"
    else
        "stable"
    end

    (trend, percent_change)
end

function get_benchmark_stats(history, benchmark_path)
    runs = history[benchmark_path]
    run_numbers = sort([parse(Int, k) for k in keys(runs)])

    isempty(run_numbers) && return nothing

    latest = runs[string(run_numbers[end])]
    trend, percent_change = calculate_trend(history, benchmark_path)

    (
        latest_mean = round(get(latest, "mean_time_ns", 0) / 1e6, digits=3),
        latest_commit = get(latest, "commit_hash", "unknown"),
        latest_memory = get(latest, "memory_bytes", 0),
        latest_allocs = get(latest, "allocs", 0),
        num_runs = length(run_numbers),
        trend = trend,
        percent_change = percent_change,
        latest_timestamp = get(latest, "timestamp", "")
    )
end

function create_interactive_dashboard(data_dir="data"; port=8000, repo_url=REPO_URL)
    data = load_dashboard_data(data_dir)

    app = App() do _session
        dark_mode = Observable(false)
        percentage_mode = Observable(false)
        search_filter = Observable("")
        trend_filter = Observable("all")

        all_benchmarks = Dict{String, Any}()
        for group_name in data.groups
            history = data.histories[group_name]
            for benchmark_path in keys(history)
                stats = get_benchmark_stats(history, benchmark_path)
                isnothing(stats) && continue
                all_benchmarks[benchmark_path] = (
                    group = group_name,
                    history = history,
                    stats = stats
                )
            end
        end

        benchmark_figures = Dict{String, Figure}()
        benchmark_axes = Dict{String, Axis}()

        css_styles = """
            .dashboard-container {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                padding: 20px;
            }
            .main-content {
                max-width: 1600px;
                margin: 0 auto;
                background: white;
                border-radius: 20px;
                box-shadow: 0 20px 60px rgba(0,0,0,0.3);
                overflow: hidden;
            }
            .header {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 40px;
                text-align: center;
            }
            .header h1 {
                font-size: 3em;
                margin: 0 0 10px 0;
                text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
            }
            .header p {
                font-size: 1.2em;
                opacity: 0.9;
                margin: 0;
            }
            .stats-panel {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
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
                transition: transform 0.3s ease;
            }
            .stat-card:hover {
                transform: translateY(-5px);
            }
            .stat-card .value {
                font-size: 2em;
                font-weight: bold;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
                background-clip: text;
            }
            .stat-card .label {
                color: #6c757d;
                font-size: 0.85em;
                text-transform: uppercase;
                letter-spacing: 1px;
                margin-top: 8px;
            }
            .controls {
                padding: 25px 30px;
                background: white;
                border-bottom: 1px solid #e9ecef;
                display: flex;
                gap: 12px;
                flex-wrap: wrap;
                align-items: center;
            }
            .btn {
                padding: 10px 20px;
                border: none;
                border-radius: 8px;
                font-size: 0.95em;
                cursor: pointer;
                font-weight: 600;
                transition: all 0.2s ease;
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
                background: #28a745 !important;
            }
            .search-box {
                flex: 1;
                min-width: 250px;
                padding: 10px 16px;
                border: 2px solid #e9ecef;
                border-radius: 8px;
                font-size: 0.95em;
            }
            .search-box:focus {
                outline: none;
                border-color: #667eea;
            }
            .select-box {
                padding: 10px 16px;
                border: 2px solid #e9ecef;
                border-radius: 8px;
                font-size: 0.95em;
                min-width: 140px;
            }
            .benchmarks {
                padding: 30px;
            }
            .benchmark-item {
                background: white;
                border: 2px solid #e9ecef;
                border-radius: 12px;
                margin-bottom: 25px;
                overflow: hidden;
                transition: border-color 0.3s ease;
            }
            .benchmark-item:hover {
                border-color: #667eea;
            }
            .benchmark-header {
                background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
                padding: 18px 20px;
                display: flex;
                justify-content: space-between;
                align-items: center;
                flex-wrap: wrap;
                gap: 12px;
            }
            .benchmark-name {
                font-size: 1.2em;
                font-weight: bold;
                color: #2c3e50;
                display: flex;
                align-items: center;
                gap: 10px;
            }
            .trend-badge {
                padding: 5px 12px;
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
                font-size: 0.75em;
                color: #6c757d;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }
            .stat-val {
                display: block;
                font-weight: bold;
                color: #2c3e50;
                font-size: 1em;
            }
            .stat-val a {
                color: #667eea;
                text-decoration: none;
            }
            .stat-val a:hover {
                text-decoration: underline;
            }
            .plot-container {
                padding: 15px;
                min-height: 380px;
            }
            .footer {
                background: #2c3e50;
                color: white;
                text-align: center;
                padding: 20px;
            }
            .footer a {
                color: #667eea;
                text-decoration: none;
            }
            .no-results {
                text-align: center;
                padding: 50px;
                color: #6c757d;
            }

            .dark-mode .main-content {
                background: #2c3e50;
            }
            .dark-mode .stats-panel {
                background: #34495e;
            }
            .dark-mode .stat-card {
                background: #2c3e50;
                color: #ecf0f1;
            }
            .dark-mode .controls {
                background: #34495e;
                border-bottom-color: #4a5568;
            }
            .dark-mode .benchmarks {
                background: #2c3e50;
            }
            .dark-mode .benchmark-item {
                background: #34495e;
                border-color: #4a5568;
            }
            .dark-mode .benchmark-header {
                background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%);
            }
            .dark-mode .benchmark-name {
                color: #ecf0f1;
            }
            .dark-mode .stat-val {
                color: #ecf0f1;
            }
            .dark-mode .search-box,
            .dark-mode .select-box {
                background: #2c3e50;
                color: #ecf0f1;
                border-color: #4a5568;
            }
        """

        function render_stats_panel()
            last_updated = isnothing(data.stats.last_run) ? "Unknown" : format_time_ago(data.stats.last_run)

            DOM.div(
                DOM.div(
                    DOM.div(string(data.stats.total_benchmarks), class="value"),
                    DOM.div("Total Benchmarks", class="label"),
                    class="stat-card"
                ),
                DOM.div(
                    DOM.div(string(data.stats.total_runs), class="value"),
                    DOM.div("Total Runs", class="label"),
                    class="stat-card"
                ),
                DOM.div(
                    DOM.div(format_time_short(data.stats.fastest[2]), class="value", style="-webkit-text-fill-color: #27ae60;"),
                    DOM.div("Fastest", class="label"),
                    class="stat-card"
                ),
                DOM.div(
                    DOM.div(format_time_short(data.stats.slowest[2]), class="value", style="-webkit-text-fill-color: #e74c3c;"),
                    DOM.div("Slowest", class="label"),
                    class="stat-card"
                ),
                DOM.div(
                    DOM.div(last_updated, class="value", style="font-size: 1.1em;"),
                    DOM.div("Last Updated", class="label"),
                    class="stat-card"
                ),
                class="stats-panel"
            )
        end

        function create_benchmark_plot(benchmark_path, bench_data)
            history = bench_data.history

            fig = Figure(size=(1200, 350), backgroundcolor=:transparent)
            ax = Axis(fig[1, 1],
                xlabel="Commit",
                ylabel=percentage_mode[] ? "Change (%)" : "Time (ms)",
                backgroundcolor=dark_mode[] ? RGBf(0.17, 0.24, 0.31) : :white,
                xgridcolor=dark_mode[] ? RGBf(0.3, 0.3, 0.3) : RGBf(0.9, 0.9, 0.9),
                ygridcolor=dark_mode[] ? RGBf(0.3, 0.3, 0.3) : RGBf(0.9, 0.9, 0.9),
                xlabelcolor=dark_mode[] ? :white : :black,
                ylabelcolor=dark_mode[] ? :white : :black,
                xticklabelcolor=dark_mode[] ? :white : :black,
                yticklabelcolor=dark_mode[] ? :white : :black
            )

            plot_data_mean = prepare_plot_data(history, benchmark_path; metric=:mean, as_percentage=percentage_mode[])
            plot_data_min = prepare_plot_data(history, benchmark_path; metric=:min, as_percentage=percentage_mode[])
            plot_data_median = prepare_plot_data(history, benchmark_path; metric=:median, as_percentage=percentage_mode[])

            if !isempty(plot_data_mean.y)
                x_values = collect(1:length(plot_data_mean.y))

                lines!(ax, x_values, plot_data_mean.y,
                    color=RGBf(0.4, 0.49, 0.92),
                    linewidth=3,
                    label="Mean")
                scatter!(ax, x_values, plot_data_mean.y,
                    color=RGBf(0.4, 0.49, 0.92),
                    markersize=10,
                    inspector_label = (self, i, p) -> begin
                        idx = round(Int, p[1])
                        if idx >= 1 && idx <= length(plot_data_mean.commit_hashes)
                            """
                            Commit: $(plot_data_mean.commit_hashes[idx])
                            Mean: $(round(plot_data_mean.mean[idx], digits=3)) ms
                            Median: $(round(plot_data_median.median[idx], digits=3)) ms
                            Min: $(round(plot_data_min.min[idx], digits=3)) ms
                            Memory: $(format_memory(plot_data_mean.memory[idx]))
                            Allocs: $(plot_data_mean.allocs[idx])
                            Julia: $(plot_data_mean.julia_versions[idx])
                            Date: $(format_date_nice(plot_data_mean.timestamps[idx]))
                            """
                        else
                            ""
                        end
                    end)

                lines!(ax, x_values, plot_data_min.y,
                    color=RGBf(0.15, 0.68, 0.38),
                    linewidth=2,
                    linestyle=:dash,
                    label="Min")

                lines!(ax, x_values, plot_data_median.y,
                    color=RGBf(0.95, 0.61, 0.07),
                    linewidth=2,
                    linestyle=:dot,
                    label="Median")

                commit_labels = [format_commit_hash(h) for h in plot_data_mean.commit_hashes]
                ax.xticks = (x_values, commit_labels)
                ax.xticklabelrotation = π/6
            end

            axislegend(ax, position=:rt, backgroundcolor=dark_mode[] ? RGBAf(0.2, 0.2, 0.2, 0.8) : RGBAf(1, 1, 1, 0.8))
            DataInspector(fig)

            benchmark_figures[benchmark_path] = fig
            benchmark_axes[benchmark_path] = ax

            fig
        end

        function update_all_plots()
            for (benchmark_path, bench_data) in all_benchmarks
                haskey(benchmark_axes, benchmark_path) || continue

                ax = benchmark_axes[benchmark_path]
                history = bench_data.history

                empty!(ax)

                ax.ylabel = percentage_mode[] ? "Change (%)" : "Time (ms)"
                ax.backgroundcolor = dark_mode[] ? RGBf(0.17, 0.24, 0.31) : :white
                ax.xgridcolor = dark_mode[] ? RGBf(0.3, 0.3, 0.3) : RGBf(0.9, 0.9, 0.9)
                ax.ygridcolor = dark_mode[] ? RGBf(0.3, 0.3, 0.3) : RGBf(0.9, 0.9, 0.9)
                ax.xlabelcolor = dark_mode[] ? :white : :black
                ax.ylabelcolor = dark_mode[] ? :white : :black
                ax.xticklabelcolor = dark_mode[] ? :white : :black
                ax.yticklabelcolor = dark_mode[] ? :white : :black

                plot_data_mean = prepare_plot_data(history, benchmark_path; metric=:mean, as_percentage=percentage_mode[])
                plot_data_min = prepare_plot_data(history, benchmark_path; metric=:min, as_percentage=percentage_mode[])
                plot_data_median = prepare_plot_data(history, benchmark_path; metric=:median, as_percentage=percentage_mode[])

                isempty(plot_data_mean.y) && continue

                x_values = collect(1:length(plot_data_mean.y))

                lines!(ax, x_values, plot_data_mean.y,
                    color=RGBf(0.4, 0.49, 0.92),
                    linewidth=3,
                    label="Mean")
                scatter!(ax, x_values, plot_data_mean.y,
                    color=RGBf(0.4, 0.49, 0.92),
                    markersize=10)

                lines!(ax, x_values, plot_data_min.y,
                    color=RGBf(0.15, 0.68, 0.38),
                    linewidth=2,
                    linestyle=:dash,
                    label="Min")

                lines!(ax, x_values, plot_data_median.y,
                    color=RGBf(0.95, 0.61, 0.07),
                    linewidth=2,
                    linestyle=:dot,
                    label="Median")

                commit_labels = [format_commit_hash(h) for h in plot_data_mean.commit_hashes]
                ax.xticks = (x_values, commit_labels)
                ax.xticklabelrotation = π/6

                axislegend(ax, position=:rt, backgroundcolor=dark_mode[] ? RGBAf(0.2, 0.2, 0.2, 0.8) : RGBAf(1, 1, 1, 0.8))
            end
        end

        function reset_all_zoom()
            for (_, ax) in benchmark_axes
                reset_limits!(ax)
            end
        end

        on(dark_mode) do _
            update_all_plots()
        end

        on(percentage_mode) do _
            update_all_plots()
        end

        function render_benchmark_card(benchmark_path, bench_data)
            stats = bench_data.stats

            trend_badge_elem = if stats.num_runs > 1
                arrow = stats.trend == "faster" ? "↓" : (stats.trend == "slower" ? "↑" : "→")
                sign = stats.percent_change > 0 ? "+" : ""
                DOM.span("$arrow $(sign)$(stats.percent_change)%", class="trend-badge trend-$(stats.trend)")
            else
                DOM.span()
            end

            commit_short = stats.latest_commit[1:min(7, length(stats.latest_commit))]
            commit_link_elem = DOM.a(commit_short, href="$(repo_url)/commit/$(stats.latest_commit)", target="_blank")

            fig = create_benchmark_plot(benchmark_path, bench_data)

            DOM.div(
                DOM.div(
                    DOM.div(
                        DOM.span(benchmark_path),
                        trend_badge_elem,
                        class="benchmark-name"
                    ),
                    DOM.div(
                        DOM.div(
                            DOM.span("Latest", class="stat-key"),
                            DOM.span("$(stats.latest_mean) ms", class="stat-val"),
                            class="stat"
                        ),
                        DOM.div(
                            DOM.span("Commit", class="stat-key"),
                            DOM.span(commit_link_elem, class="stat-val"),
                            class="stat"
                        ),
                        DOM.div(
                            DOM.span("Memory", class="stat-key"),
                            DOM.span(format_memory(stats.latest_memory), class="stat-val"),
                            class="stat"
                        ),
                        DOM.div(
                            DOM.span("Allocs", class="stat-key"),
                            DOM.span(string(stats.latest_allocs), class="stat-val"),
                            class="stat"
                        ),
                        DOM.div(
                            DOM.span("Runs", class="stat-key"),
                            DOM.span(string(stats.num_runs), class="stat-val"),
                            class="stat"
                        ),
                        class="benchmark-stats"
                    ),
                    class="benchmark-header"
                ),
                DOM.div(fig, class="plot-container"),
                class="benchmark-item"
            )
        end

        filtered_benchmarks = map(search_filter, trend_filter) do search, trend
            filter(collect(all_benchmarks)) do (path, bench_data)
                matches_search = isempty(search) || occursin(lowercase(search), lowercase(path))
                matches_trend = trend == "all" || bench_data.stats.trend == trend
                matches_search && matches_trend
            end |> x -> sort(x, by=first)
        end

        benchmarks_content = map(filtered_benchmarks) do benchmarks
            if isempty(benchmarks)
                return DOM.div(
                    DOM.h2("No benchmarks found"),
                    DOM.p("Try a different search term or filter"),
                    class="no-results"
                )
            end

            cards = [render_benchmark_card(path, bench_data) for (path, bench_data) in benchmarks]
            DOM.div(cards..., class="benchmarks")
        end

        csv_data = JSON.json(data.histories)

        dark_mode_class = map(dark_mode) do dm
            dm ? "dashboard-container dark-mode" : "dashboard-container"
        end

        percentage_btn_class = map(percentage_mode) do pm
            pm ? "btn btn-primary active" : "btn btn-primary"
        end

        dark_btn_class = map(dark_mode) do dm
            dm ? "btn btn-secondary active" : "btn btn-secondary"
        end

        return DOM.div(
            DOM.style(css_styles),
            DOM.div(
                DOM.div(
                    DOM.div(
                        DOM.h1("📊 BenchmarkExplorer"),
                        DOM.p("Interactive Benchmark Dashboard"),
                        class="header"
                    ),
                    render_stats_panel(),
                    DOM.div(
                        DOM.button("% Change Mode",
                            class=percentage_btn_class,
                            onclick=js"() => { $(percentage_mode).notify($(!percentage_mode[])); }"
                        ),
                        DOM.button("🌙 Dark Mode",
                            class=dark_btn_class,
                            onclick=js"() => { $(dark_mode).notify($(!dark_mode[])); }"
                        ),
                        DOM.button("🔍 Reset Zoom",
                            class="btn btn-secondary",
                            onclick=Bonito.JSCode("() => { $reset_all_zoom(); }")
                        ),
                        DOM.button("📥 Export CSV",
                            class="btn btn-secondary",
                            onclick=Bonito.JSCode("""
                                () => {
                                    const data = $csv_data;
                                    let csv = 'Group,Benchmark,Run,Timestamp,Mean (ms),Min (ms),Median (ms),Memory (bytes),Allocations\\n';
                                    for (const [group, benchmarks] of Object.entries(data)) {
                                        for (const [benchmark, runs] of Object.entries(benchmarks)) {
                                            for (const [runNum, run] of Object.entries(runs)) {
                                                const mean = ((run.mean_time_ns || 0) / 1e6).toFixed(3);
                                                const min = ((run.min_time_ns || 0) / 1e6).toFixed(3);
                                                const median = ((run.median_time_ns || 0) / 1e6).toFixed(3);
                                                csv += `"\${group}","\${benchmark}",\${runNum},"\${run.timestamp || ''}",\${mean},\${min},\${median},\${run.memory_bytes || 0},\${run.allocs || 0}\\n`;
                                            }
                                        }
                                    }
                                    const blob = new Blob([csv], { type: 'text/csv' });
                                    const url = URL.createObjectURL(blob);
                                    const a = document.createElement('a');
                                    a.href = url;
                                    a.download = 'benchmarks.csv';
                                    a.click();
                                    URL.revokeObjectURL(url);
                                }
                            """)
                        ),
                        DOM.select(
                            DOM.option("All Trends", value="all"),
                            DOM.option("↓ Faster", value="faster"),
                            DOM.option("↑ Slower", value="slower"),
                            DOM.option("→ Stable", value="stable"),
                            class="select-box",
                            onchange=js"(e) => { $(trend_filter).notify(e.target.value); }"
                        ),
                        DOM.input(
                            type="text",
                            placeholder="🔍 Search benchmarks...",
                            class="search-box",
                            oninput=js"(e) => { $(search_filter).notify(e.target.value); }"
                        ),
                        class="controls"
                    ),
                    benchmarks_content,
                    DOM.div(
                        DOM.p("Generated by ", DOM.a("BenchmarkExplorer.jl", href=repo_url, target="_blank"), " • Powered by Bonito.jl + WGLMakie.jl"),
                        class="footer"
                    ),
                    class="main-content"
                ),
                class=dark_mode_class
            )
        )
    end

    server = Bonito.Server(app, "0.0.0.0", port)
    server
end

function main()
    port = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 8000
    data_dir = length(ARGS) >= 2 ? ARGS[2] : "data"

    server = create_interactive_dashboard(data_dir; port=port)
    wait(server)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

