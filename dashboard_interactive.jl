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

function format_date_nice(iso_str::String)
    try
        dt = DateTime(split(iso_str, ".")[1])
        Dates.format(dt, "d u yyyy, HH:MM")
    catch
        iso_str
    end
end

function fmt_memory(bytes)
    bytes < 1024 && return "$bytes B"
    bytes < 1024^2 && return @sprintf("%.1f KB", bytes / 1024)
    bytes < 1024^3 && return @sprintf("%.1f MB", bytes / 1024^2)
    return @sprintf("%.2f GB", bytes / 1024^3)
end

function fmt_time(ns)
    ns < 1e3  && return @sprintf("%.0f ns", ns)
    ns < 1e6  && return @sprintf("%.1f μs", ns / 1e3)
    ns < 1e9  && return @sprintf("%.2f ms", ns / 1e6)
    return @sprintf("%.2f s", ns / 1e9)
end

function sparkline_svg(values::Vector{Float64}, w=80, h=28)
    clean = filter(isfinite, values)
    length(clean) < 2 && return ""
    mn, mx = minimum(clean), maximum(clean)
    rng = mx - mn > 0 ? mx - mn : 1.0
    n = length(values)
    pts = join(["$(round((i-1)/max(n-1,1)*w,digits=1)),$(round(h-((v-mn)/rng)*(h-4)-2,digits=1))"
                for (i, v) in enumerate(values)], " ")
    """<svg width="$w" height="$h" viewBox="0 0 $w $h" style="vertical-align:middle;margin-left:8px;opacity:0.6"><polyline fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round" points="$pts"/></svg>"""
end

function get_benchmark_stats(history, benchmark_path)
    runs = history[benchmark_path]
    run_numbers = sort([parse(Int, k) for k in keys(runs)],
                       by = k -> get(runs[string(k)], "timestamp", ""))
    isempty(run_numbers) && return nothing
    latest = runs[string(run_numbers[end])]

    trend, pct = if length(run_numbers) >= 2
        baseline = runs[string(run_numbers[1])]
        bm = get(baseline, "mean_time_ns", 1.0) / 1e6
        lm = get(latest,   "mean_time_ns", 0.0) / 1e6
        bm == 0 ? ("stable", 0.0) : begin
            p = round(((lm / bm) - 1) * 100, digits=2)
            t = p < -5 ? "faster" : (p > 5 ? "slower" : "stable")
            (t, p)
        end
    else
        ("stable", 0.0)
    end

    (
        latest_mean   = round(get(latest, "mean_time_ns", 0.0) / 1e6, digits=3),
        latest_commit = get(latest, "commit_hash", "unknown"),
        latest_memory = get(latest, "memory_bytes", 0),
        latest_allocs = get(latest, "allocs", 0),
        num_runs      = length(run_numbers),
        trend         = trend,
        percent_change = pct,
        latest_timestamp = get(latest, "timestamp", "")
    )
end

const DASHBOARD_CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'JetBrains Mono', SFMono-Regular, Consolas, monospace;
       background: #fff; color: #191919; }

.header { background: #fff; padding: 28px 40px 20px;
          border-bottom: 2px solid #191919; }
.header h1 { font-size: 1.3em; font-weight: 700; margin-bottom: 4px; }
.header p  { font-size: 0.78em; color: #999; }

.stats-panel { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px,1fr));
               background: #f7f6f3; border-bottom: 2px solid #191919; }
.stat-card   { padding: 18px 22px; border-right: 1px solid #e9e9e7; text-align: center; }
.stat-card:last-child { border-right: none; }
.stat-card .value { font-size: 1.6em; font-weight: 700; color: #191919; }
.stat-card .label { color: #999; font-size: 0.7em; text-transform: uppercase;
                    letter-spacing: 0.4px; margin-top: 5px; }

.controls { padding: 10px 32px; background: #fff; border-bottom: 2px solid #191919;
            position: sticky; top: 0; z-index: 100;
            display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }

.btn { padding: 7px 14px; border: 2px solid #191919; border-radius: 8px;
       font-size: 0.82em; cursor: pointer; font-weight: 600;
       font-family: inherit; background: #fff; color: #191919;
       transition: background 0.12s; white-space: nowrap; }
.btn:hover  { background: #f7f6f3; }
.btn.active { background: #191919; color: #fff; }
.btn-group  { display: flex; border: 2px solid #191919; border-radius: 8px;
              overflow: hidden; flex-shrink: 0; }
.btn-group .btn { border: none; border-radius: 0;
                  border-left: 1px solid #ccc; padding: 7px 11px; }
.btn-group .btn:first-child { border-left: none; }
.btn-group .btn.active { background: #191919; color: #fff; }

.search-box, .select-box {
    padding: 7px 13px; border: 2px solid #191919; border-radius: 8px;
    font-size: 0.88em; font-family: inherit;
    background: #fff; color: #191919; }
.search-box { flex: 1; min-width: 180px; }
.search-box:focus, .select-box:focus { outline: none; }

.benchmarks-wrap { padding: 24px 32px; }

.tree-toggle { display: flex; align-items: center; gap: 10px;
               padding: 10px 16px; cursor: pointer;
               background: #f7f6f3; border: 2px solid #191919;
               border-radius: 8px; margin-bottom: 12px;
               font-weight: 700; font-size: 0.9em; list-style: none; }
.tree-toggle::-webkit-details-marker { display: none; }
.tree-toggle .count { font-weight: 400; color: #999; font-size: 0.8em; margin-left: auto; }
details[open] > summary.tree-toggle { border-radius: 8px 8px 0 0; margin-bottom: 0; }
details > .tree-children { border: 2px solid #191919; border-top: none;
                           border-radius: 0 0 8px 8px; padding: 12px;
                           margin-bottom: 16px; }

.benchmark-item { border: 2px solid #191919; border-radius: 10px;
                  margin-bottom: 14px; overflow: hidden;
                  transition: transform 0.12s, box-shadow 0.12s;
                  animation: fadeIn 0.2s ease both; }
.benchmark-item:hover { transform: translateY(-2px);
                        box-shadow: 0 6px 18px rgba(0,0,0,0.1); }
.benchmark-item.trend-faster { border-left: 5px solid #27ae60; }
.benchmark-item.trend-slower { border-left: 5px solid #e74c3c; }
.benchmark-item.trend-stable { border-left: 5px solid #ccc; }

@keyframes fadeIn { from { opacity:0; transform:translateY(6px); }
                    to   { opacity:1; transform:translateY(0); } }

.benchmark-header { background: #f7f6f3; padding: 14px 18px;
                    display: flex; justify-content: space-between;
                    align-items: center; flex-wrap: wrap; gap: 10px;
                    border-bottom: 1px solid #e9e9e7; }
.benchmark-name  { font-size: 0.9em; font-weight: 600; color: #191919;
                   display: flex; align-items: center; gap: 8px;
                   font-family: 'JetBrains Mono', monospace; }
.trend-badge { padding: 2px 7px; border-radius: 3px; font-size: 0.73em;
               font-weight: 600; }
.trend-faster { background: #e6f4ea; color: #1e7e34; border: 1px solid #c3e6cb; }
.trend-slower { background: #fce8e8; color: #b91c1c; border: 1px solid #f5c6cb; }
.trend-stable { background: #f0f0f0; color: #555;    border: 1px solid #ddd; }
.benchmark-stats { display: flex; gap: 20px; flex-wrap: wrap; }
.stat { text-align: center; }
.stat-key { display: block; font-size: 0.7em; color: #787774;
            text-transform: uppercase; letter-spacing: 0.4px; margin-bottom: 2px; }
.stat-val { display: block; font-weight: 700; color: #191919; font-size: 0.88em; }
.stat-val a { color: #191919; text-decoration: underline; }
.plot-container { padding: 10px 14px; min-height: 340px; }

.compact-mode .plot-container { display: none !important; }
.compact-mode .benchmark-item { margin-bottom: 6px; }
.compact-mode .benchmark-header { border-bottom: none; }

.heatmap-wrap { overflow-x: auto; padding: 24px 32px;
                display: flex; justify-content: center; }
.hm-table { border-collapse: separate; border-spacing: 2px; white-space: nowrap; }
.hm-table th { padding: 4px 8px; font-weight: 600; font-size: 0.88em; color: #555;
               border-bottom: 2px solid #191919; }
.hm-table td { height: 28px; min-width: 38px; text-align: center;
               font-size: 0.82em; border-radius: 3px;
               transition: opacity 0.12s; cursor: pointer; }
.hm-table tr:hover td { opacity: 0.82; }
.hm-name { padding: 4px 14px 4px 4px !important; text-align: left !important;
           max-width: 260px; overflow: hidden; text-overflow: ellipsis;
           font-family: monospace; font-size: 0.9em; }

.compare-panel { padding: 20px 32px; }
.compare-selects { display: flex; gap: 12px; align-items: center;
                   flex-wrap: wrap; margin-bottom: 20px; }
.cmp-table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
.cmp-table th { padding: 8px 12px; text-align: left;
                border-bottom: 2px solid #191919;
                font-size: 0.78em; text-transform: uppercase;
                letter-spacing: 0.4px; color: #999; }
.cmp-table td { padding: 7px 12px; border-bottom: 1px solid #e9e9e7; }
.cmp-table tr:hover td { background: #f7f6f3; }

.no-results { text-align: center; padding: 60px; color: #999; }

.footer { text-align: center; padding: 20px; font-size: 0.73em; color: #aaa;
          border-top: 1px solid #e9e9e7; margin-top: 16px; }
.footer a { color: #666; text-decoration: none; }

/* ── dark mode ─────────────────────────────────── */
.dark { background: #191919; color: #e9e9e7; }
.dark .header  { background: #191919; color: #e9e9e7; border-bottom-color: #383838; }
.dark .header p { color: #666; }
.dark .stats-panel { background: #252525; border-bottom-color: #383838; }
.dark .stat-card   { border-right-color: #333; }
.dark .stat-card .value { color: #e9e9e7; }
.dark .controls { background: #252525; border-bottom-color: #383838; }
.dark .btn { background: #252525; color: #e9e9e7; border-color: #383838; }
.dark .btn:hover  { background: #333; }
.dark .btn.active { background: #e9e9e7; color: #191919; border-color: #e9e9e7; }
.dark .btn-group  { border-color: #383838; }
.dark .btn-group .btn { border-left-color: #444; }
.dark .search-box, .dark .select-box { background: #252525; color: #e9e9e7; border-color: #383838; }
.dark .benchmarks-wrap { background: #191919; }
.dark .tree-toggle { background: #252525; border-color: #383838; color: #e9e9e7; }
.dark .tree-toggle .count { color: #666; }
.dark details > .tree-children { border-color: #383838; }
.dark .benchmark-item { border-color: #383838; }
.dark .benchmark-item.trend-faster { border-left-color: #2ecc71; }
.dark .benchmark-item.trend-slower { border-left-color: #e74c3c; }
.dark .benchmark-item.trend-stable { border-left-color: #555; }
.dark .benchmark-item:hover { border-color: #666; }
.dark .benchmark-header { background: #252525; border-bottom-color: #333; }
.dark .benchmark-name  { color: #e9e9e7; }
.dark .stat-key { color: #888; }
.dark .stat-val { color: #e9e9e7; }
.dark .stat-val a { color: #e9e9e7; }
.dark .trend-faster { background: #0d2b14; color: #5cc475; border-color: #1e5c2e; }
.dark .trend-slower { background: #2b0d0d; color: #f07070; border-color: #5c1e1e; }
.dark .trend-stable { background: #222; color: #888; border-color: #444; }
.dark .hm-table th { border-bottom-color: #444; color: #aaa; }
.dark .hm-name { color: #e9e9e7; }
.dark .cmp-table th { border-bottom-color: #444; color: #888; }
.dark .cmp-table td { border-bottom-color: #333; color: #e9e9e7; }
.dark .cmp-table tr:hover td { background: #252525; }
.dark .footer { border-top-color: #333; color: #555; }
"""

function create_interactive_dashboard(data_dir="data"; port=8000, repo_url=REPO_URL)
    data = load_dashboard_data(data_dir)

    app = App() do _session
        dark_mode       = Observable(false)
        percentage_mode = Observable(false)
        search_filter   = Observable("")
        trend_filter    = Observable("all")
        max_runs_obs    = Observable{Union{Nothing,Int}}(nothing)
        view_mode       = Observable("normal")
        compare_a       = Observable("")
        compare_b       = Observable("")

        all_benchmarks = Dict{String, Any}()
        for group_name in data.groups
            history = data.histories[group_name]
            for benchmark_path in keys(history)
                stats = get_benchmark_stats(history, benchmark_path)
                isnothing(stats) && continue
                all_benchmarks[benchmark_path] = (
                    group   = group_name,
                    history = history,
                    stats   = stats
                )
            end
        end

        commit_times = Dict{String,String}()
        for (path, bd) in all_benchmarks
            for (_, run) in bd.history[path]
                h = get(run, "commit_hash", "")
                t = get(run, "timestamp",   "")
                !isempty(h) && !haskey(commit_times, h) && (commit_times[h] = t)
            end
        end
        all_commits = sort(collect(keys(commit_times)), by = h -> get(commit_times, h, ""))

        benchmark_figures = Dict{String,Figure}()
        benchmark_axes    = Dict{String,Axis}()

        function make_figure(path, bench_data)
            history = bench_data.history
            fig = Figure(size=(1100, 310), backgroundcolor=:transparent)
            ax  = Axis(fig[1,1],
                xlabel = "Commit",
                ylabel = percentage_mode[] ? "Δ %" : "ms",
                backgroundcolor    = dark_mode[] ? RGBf(0.1,0.1,0.1) : :white,
                xgridcolor         = dark_mode[] ? RGBf(0.25,0.25,0.25) : RGBf(0.92,0.92,0.92),
                ygridcolor         = dark_mode[] ? RGBf(0.25,0.25,0.25) : RGBf(0.92,0.92,0.92),
                xlabelcolor        = dark_mode[] ? :white : :black,
                ylabelcolor        = dark_mode[] ? :white : :black,
                xticklabelcolor    = dark_mode[] ? :white : :black,
                yticklabelcolor    = dark_mode[] ? :white : :black,
                xticklabelsize     = 10,
            )
            pd_mean   = prepare_plot_data(history, path; metric=:mean,   as_percentage=percentage_mode[], max_runs=max_runs_obs[])
            pd_min    = prepare_plot_data(history, path; metric=:min,    as_percentage=percentage_mode[], max_runs=max_runs_obs[])
            pd_median = prepare_plot_data(history, path; metric=:median, as_percentage=percentage_mode[], max_runs=max_runs_obs[])

            if !isempty(pd_mean.y)
                xs = collect(1:length(pd_mean.y))
                mc = dark_mode[] ? :white : :black
                lines!(ax,  xs, pd_mean.y,   color=mc,                     linewidth=2, label="Mean")
                scatter!(ax, xs, pd_mean.y,  color=mc,                     markersize=7,
                    inspector_label = (self, i, p) -> begin
                        idx = round(Int, p[1])
                        1 <= idx <= length(pd_mean.commit_hashes) || return ""
                        "Commit: $(pd_mean.commit_hashes[idx][1:min(7,end)])\nMean:   $(round(pd_mean.mean[idx],   digits=3)) ms\nMedian: $(round(pd_mean.median[idx], digits=3)) ms\nMin:    $(round(pd_mean.min[idx],    digits=3)) ms\nMemory: $(fmt_memory(pd_mean.memory[idx]))\nAllocs: $(pd_mean.allocs[idx])\nDate:   $(format_date_nice(pd_mean.timestamps[idx]))"
                    end)
                !isempty(pd_min.y)    && lines!(ax, xs, pd_min.y,    color=RGBf(0.5,0.5,0.5), linewidth=1.5, linestyle=:dash, label="Min")
                !isempty(pd_median.y) && lines!(ax, xs, pd_median.y, color=RGBf(0.5,0.5,0.5), linewidth=1.5, linestyle=:dot,  label="Median")
                commit_labels = [format_commit_hash(h) for h in pd_mean.commit_hashes]
                ax.xticks = (xs, commit_labels)
                ax.xticklabelrotation = π/4
            end
            axislegend(ax, position=:rb,
                backgroundcolor = dark_mode[] ? RGBAf(0.15,0.15,0.15,0.9) : RGBAf(1,1,1,0.9))
            DataInspector(fig)
            benchmark_figures[path] = fig
            benchmark_axes[path]    = ax
            fig
        end

        for (path, bd) in sort(collect(all_benchmarks), by=first)
            make_figure(path, bd)
        end

        function update_plots()
            for (path, bd) in all_benchmarks
                haskey(benchmark_axes, path) || continue
                ax      = benchmark_axes[path]
                history = bd.history
                empty!(ax)
                ax.ylabel              = percentage_mode[] ? "Δ %" : "ms"
                ax.backgroundcolor     = dark_mode[] ? RGBf(0.1,0.1,0.1) : :white
                ax.xgridcolor          = dark_mode[] ? RGBf(0.25,0.25,0.25) : RGBf(0.92,0.92,0.92)
                ax.ygridcolor          = dark_mode[] ? RGBf(0.25,0.25,0.25) : RGBf(0.92,0.92,0.92)
                ax.xlabelcolor         = dark_mode[] ? :white : :black
                ax.ylabelcolor         = dark_mode[] ? :white : :black
                ax.xticklabelcolor     = dark_mode[] ? :white : :black
                ax.yticklabelcolor     = dark_mode[] ? :white : :black

                pd_mean   = prepare_plot_data(history, path; metric=:mean,   as_percentage=percentage_mode[], max_runs=max_runs_obs[])
                pd_min    = prepare_plot_data(history, path; metric=:min,    as_percentage=percentage_mode[], max_runs=max_runs_obs[])
                pd_median = prepare_plot_data(history, path; metric=:median, as_percentage=percentage_mode[], max_runs=max_runs_obs[])
                isempty(pd_mean.y) && continue

                xs = collect(1:length(pd_mean.y))
                mc = dark_mode[] ? :white : :black
                lines!(ax,  xs, pd_mean.y,  color=mc,                     linewidth=2, label="Mean")
                scatter!(ax, xs, pd_mean.y, color=mc,                     markersize=7)
                !isempty(pd_min.y)    && lines!(ax, xs, pd_min.y,    color=RGBf(0.5,0.5,0.5), linewidth=1.5, linestyle=:dash, label="Min")
                !isempty(pd_median.y) && lines!(ax, xs, pd_median.y, color=RGBf(0.5,0.5,0.5), linewidth=1.5, linestyle=:dot,  label="Median")
                commit_labels = [format_commit_hash(h) for h in pd_mean.commit_hashes]
                ax.xticks = (xs, commit_labels)
                ax.xticklabelrotation = π/4
                axislegend(ax, position=:rb,
                    backgroundcolor = dark_mode[] ? RGBAf(0.15,0.15,0.15,0.9) : RGBAf(1,1,1,0.9))
            end
        end

        on(dark_mode)       do _; update_plots(); end
        on(percentage_mode) do _; update_plots(); end
        on(max_runs_obs)    do _; update_plots(); end

        n_faster = count(bd -> bd.stats.trend == "faster", values(all_benchmarks))
        n_slower = count(bd -> bd.stats.trend == "slower", values(all_benchmarks))
        last_upd = isnothing(data.stats.last_run) ? "—" :
                   Dates.format(data.stats.last_run, "d u yyyy")

        stats_panel = DOM.div(
            DOM.div(DOM.div(string(data.stats.total_benchmarks), class="value"),
                    DOM.div("Benchmarks", class="label"), class="stat-card"),
            DOM.div(DOM.div(string(data.stats.total_runs), class="value"),
                    DOM.div("Total Runs", class="label"), class="stat-card"),
            DOM.div(DOM.div(fmt_time(data.stats.fastest[2]), class="value",
                            style="color:$(n_faster>0 ? "#27ae60" : "inherit")"),
                    DOM.div("Fastest", class="label"), class="stat-card"),
            DOM.div(DOM.div(fmt_time(data.stats.slowest[2]), class="value",
                            style="color:#e74c3c"),
                    DOM.div("Slowest", class="label"), class="stat-card"),
            DOM.div(DOM.div("""<span style="color:#27ae60">↓$n_faster</span> <span style="color:#e74c3c;margin-left:6px">↑$n_slower</span>""",
                            class="value", style="font-size:1.2em"),
                    DOM.div("Trends", class="label"), class="stat-card"),
            DOM.div(DOM.div(last_upd, class="value", style="font-size:1em"),
                    DOM.div("Last Run", class="label"), class="stat-card"),
            class="stats-panel"
        )

        function build_benchmark_item(path, bd)
            stats  = bd.stats
            history = bd.history
            fig = benchmark_figures[path]

            mean_vals = [get(run, "mean_time_ns", 0.0) / 1e6
                         for run in values(history[path])]
            spark = sparkline_svg(sort(mean_vals))

            commit_short = stats.latest_commit[1:min(7, lastindex(stats.latest_commit))]
            badge_text   = stats.num_runs > 1 ?
                (stats.trend == "faster" ? "↓" : stats.trend == "slower" ? "↑" : "→") *
                " " * (stats.percent_change > 0 ? "+" : "") * string(stats.percent_change) * "%" : ""

            DOM.div(
                DOM.div(
                    DOM.div(
                        DOM.span(split(path, "/")[end]),
                        !isempty(badge_text) ?
                            DOM.span(badge_text, class="trend-badge trend-$(stats.trend)") :
                            DOM.span(),
                        DOM.span(spark),
                        class="benchmark-name",
                    ),
                    DOM.div(
                        DOM.div(DOM.span("Latest",  class="stat-key"),
                                DOM.span("$(stats.latest_mean) ms", class="stat-val"), class="stat"),
                        DOM.div(DOM.span("Commit",  class="stat-key"),
                                DOM.span(DOM.a(commit_short,
                                    href="$repo_url/commit/$(stats.latest_commit)",
                                    target="_blank"), class="stat-val"), class="stat"),
                        DOM.div(DOM.span("Memory",  class="stat-key"),
                                DOM.span(fmt_memory(stats.latest_memory), class="stat-val"), class="stat"),
                        DOM.div(DOM.span("Allocs",  class="stat-key"),
                                DOM.span(string(stats.latest_allocs),     class="stat-val"), class="stat"),
                        DOM.div(DOM.span("Runs",    class="stat-key"),
                                DOM.span(string(stats.num_runs),          class="stat-val"), class="stat"),
                        class="benchmark-stats"
                    ),
                    class="benchmark-header"
                ),
                DOM.div(fig, class="plot-container"),
                class="benchmark-item trend-$(stats.trend)",
                Symbol("data-name")  => path,
                Symbol("data-trend") => stats.trend,
            )
        end

        function build_tree_dom(benchmarks_sorted)
            groups = Dict{String, Vector}()
            for (path, bd) in benchmarks_sorted
                g = split(path, "/")[1]
                push!(get!(groups, g, []), (path, bd))
            end
            nodes = []
            n_faster_g = count(t -> t[2].stats.trend == "faster",
                               collect(values(groups)) |> Iterators.flatten)
            for (gname, items) in sort(collect(groups), by=first)
                items_dom = [build_benchmark_item(path, bd) for (path, bd) in items]
                tf = count(i -> i[2].stats.trend == "faster", items)
                ts = count(i -> i[2].stats.trend == "slower", items)
                chips = (tf > 0 ? """<span style="color:#27ae60;font-size:0.78em">↓$tf</span> """ : "") *
                        (ts > 0 ? """<span style="color:#e74c3c;font-size:0.78em">↑$ts</span>""" : "")
                if length(groups) == 1
                    push!(nodes, DOM.div(items_dom...,))
                else
                    push!(nodes, DOM.details(
                        DOM.summary(
                            DOM.span(gname),
                            DOM.span(" $chips", style="margin-left:8px"),
                            DOM.span("$(length(items)) benchmarks", class="count"),
                            class="tree-toggle"),
                        DOM.div(items_dom..., class="tree-children"),
                        Symbol("open") => "open",
                        class="tree-node"
                    ))
                end
            end
            DOM.div(nodes..., class="benchmarks-wrap",
                id="benchmarks-container")
        end

        all_sorted = sort(collect(all_benchmarks), by=first)
        benchmarks_dom = build_tree_dom(all_sorted)

        heatmap_dom = map(view_mode, dark_mode) do mode, dm
            mode != "heatmap" && return DOM.div(style="display:none")
            bg  = dm ? "#191919" : "#fff"
            bc  = dm ? "#383838" : "#191919"
            thc = dm ? "#aaa"    : "#555"

            n_show  = isnothing(max_runs_obs[]) ? 25 : min(max_runs_obs[], 25)
            commits = all_commits[max(1, end - n_show + 1):end]
            shorts  = [c[1:min(7,end)] for c in commits]

            headers = join(["<th style='writing-mode:vertical-rl;transform:rotate(180deg);font-weight:400;padding:4px 6px;font-size:0.72em;color:$thc'>$s</th>"
                             for s in shorts], "")

            rows = ""
            for (path, bd) in sort(collect(all_benchmarks), by=first)
                cv = Dict{String,Float64}()
                for (_, run) in bd.history[path]
                    h = get(run, "commit_hash", "")
                    v = get(run, "mean_time_ns", 0.0) / 1e6
                    !isempty(h) && (cv[h] = v)
                end
                vals     = [get(cv, c, NaN) for c in commits]
                baseline = something(findfirst(!isnan, vals), nothing)
                bl_val   = isnothing(baseline) ? 1.0 : vals[baseline]
                sname    = join(split(path, "/")[max(1,end-1):end], "/")
                cells    = ""
                for v in vals
                    if isnan(v)
                        cells *= "<td style='background:$(dm ? "#2a2a2a" : "#f0f0ee");width:38px;height:28px;border-radius:3px'></td>"
                    else
                        ratio = v / bl_val
                        pct   = (ratio - 1) * 100
                        sat   = min(abs(ratio - 1) * 400, 80)
                        hue   = ratio <= 1 ? 140 : 0
                        lt    = dm ? (15 + sat * 0.4) : (96 - sat * 0.45)
                        tc    = dm ? "hsl($hue,70%,$(round(60+sat*0.3,digits=1))%)" :
                                     "hsl($hue,$(round(min(sat*2,100),digits=1))%,$(round(max(30.0,40-sat*0.3),digits=1))%)"
                        label = abs(pct) > 3 ? (pct > 0 ? "+$(round(Int,pct))%" : "$(round(Int,pct))%") : ""
                        cells *= "<td style='background:hsl($hue,$(round(sat,digits=1))%,$(round(lt,digits=1))%);color:$tc;width:38px;height:28px;border-radius:3px;text-align:center;font-size:0.78em' title='$path: $(round(v,digits=3)) ms'>$label</td>"
                    end
                end
                rows *= "<tr><td class='hm-name' style='color:$(dm ? "#e9e9e7" : "#191919")' title='$path'>$sname</td>$cells</tr>"
            end

            DOM.div(
                DOM.div("""
                <div class="heatmap-wrap" style="background:$bg">
                <table class="hm-table" style="background:$bg">
                <thead><tr><th style="padding:4px 14px 4px 4px;border-bottom:2px solid $bc;color:$thc">Benchmark</th>$headers</tr></thead>
                <tbody>$rows</tbody></table></div>"""),
                style="background:$bg"
            )
        end

        compare_dom = map(view_mode, compare_a, compare_b, dark_mode) do mode, ca, cb, dm
            mode != "compare" && return DOM.div(style="display:none")
            bg  = dm ? "#191919" : "#fff"
            bc  = dm ? "#383838" : "#191919"
            sc  = dm ? "#252525" : "#f7f6f3"
            tc  = dm ? "#e9e9e7" : "#191919"
            fc  = dm ? "#252525" : "#fff"
            fnc = dm ? "#e9e9e7" : "#191919"

            opts_a = join(["<option value='$h' $(h==ca ? "selected" : "")>$(h[1:min(7,end)])</option>"
                            for h in all_commits], "")
            opts_b = join(["<option value='$h' $(h==cb ? "selected" : "")>$(h[1:min(7,end)])</option>"
                            for h in all_commits], "")

            tbody = ""
            if !isempty(ca) && !isempty(cb) && ca != cb
                rows = []
                for (path, bd) in all_benchmarks
                    cv = Dict{String,Float64}()
                    for (_, run) in bd.history[path]
                        h = get(run, "commit_hash", "")
                        v = get(run, "mean_time_ns", 0.0) / 1e6
                        !isempty(h) && (cv[h] = v)
                    end
                    (haskey(cv,ca) && haskey(cv,cb)) || continue
                    va, vb = cv[ca], cv[cb]
                    push!(rows, (path=path, va=va, vb=vb, change=(vb/va-1)*100))
                end
                sort!(rows, by=r -> -abs(r.change))
                for r in rows
                    cc  = r.change < -5 ? (dm ? "#5cc475" : "#1e7e34") :
                          r.change >  5 ? (dm ? "#f07070" : "#b91c1c") :
                                          (dm ? "#888" : "#555")
                    sgn = r.change > 0 ? "+" : ""
                    tbody *= "<tr><td style='font-family:monospace;font-size:0.82em;padding:8px 12px;color:$tc'>$(r.path)</td><td style='padding:8px 12px;color:$tc'>$(round(r.va,digits=3)) ms</td><td style='padding:8px 12px;color:$tc'>$(round(r.vb,digits=3)) ms</td><td style='padding:8px 12px;font-weight:700;color:$cc'>$sgn$(round(r.change,digits=1))%</td></tr>"
                end
            elseif !isempty(ca) && !isempty(cb)
                tbody = "<tr><td colspan='4' style='padding:16px;color:$(dm ? "#666" : "#999")'>Select two different commits.</td></tr>"
            end

            sa = isempty(ca) ? "—" : ca[1:min(7,end)]
            sb = isempty(cb) ? "—" : cb[1:min(7,end)]

            DOM.div(DOM.div("""
            <div class="compare-panel" style="background:$bg">
              <div class="compare-selects">
                <select id="cmp-a" style="padding:8px 12px;border:2px solid $bc;border-radius:8px;font-family:inherit;background:$fc;color:$fnc">
                  <option value=''>Commit A...</option>$opts_a</select>
                <span style="color:$(dm ? "#666" : "#999")">vs</span>
                <select id="cmp-b" style="padding:8px 12px;border:2px solid $bc;border-radius:8px;font-family:inherit;background:$fc;color:$fnc">
                  <option value=''>Commit B...</option>$opts_b</select>
              </div>
              <table class="cmp-table">
                <thead><tr>
                  <th>Benchmark</th><th>$sa</th><th>$sb</th><th>Change</th>
                </tr></thead>
                <tbody>$tbody</tbody>
              </table>
            </div>"""), style="background:$bg")
        end

        client_js = Bonito.JSCode("""
        (function() {
            function filterBenchmarks() {
                const search = (document.getElementById('search-box')?.value || '').toLowerCase();
                const trend  = document.getElementById('trend-select')?.value || 'all';
                document.querySelectorAll('.benchmark-item').forEach(el => {
                    const name  = (el.dataset.name  || '').toLowerCase();
                    const tr    = el.dataset.trend || '';
                    const show  = name.includes(search) && (trend === 'all' || tr === trend);
                    el.style.display = show ? '' : 'none';
                });
            }
            document.addEventListener('input',  e => e.target.id === 'search-box'    && filterBenchmarks());
            document.addEventListener('change', e => e.target.id === 'trend-select'  && filterBenchmarks());
            document.addEventListener('change', e => {
                if (e.target.id === 'cmp-a') $(compare_a).notify(e.target.value);
                if (e.target.id === 'cmp-b') $(compare_b).notify(e.target.value);
            });
            document.addEventListener('keydown', e => {
                if (e.key === '/' && e.target.tagName !== 'INPUT' && e.target.tagName !== 'SELECT') {
                    e.preventDefault();
                    document.getElementById('search-box')?.focus();
                }
            });
        })();
        """)

        pct_cls  = map(m -> m ? "btn active" : "btn",       percentage_mode)
        dark_cls = map(m -> m ? "btn active" : "btn",       dark_mode)

        controls = DOM.div(
            DOM.button("% Change", class=pct_cls,
                onclick = js"() => { $(percentage_mode).notify(!$(percentage_mode)[]); }"),
            DOM.button("Dark", class=dark_cls,
                onclick = js"() => { $(dark_mode).notify(!$(dark_mode)[]); }"),
            DOM.button("Compact",
                class  = map(m -> m == "compact" ? "btn active" : "btn", view_mode),
                onclick = js"() => {
                    const cur = $(view_mode)[];
                    $(view_mode).notify(cur === 'compact' ? 'normal' : 'compact');
                    document.getElementById('benchmarks-container')?.classList.toggle('compact-mode', cur !== 'compact');
                }"),
            DOM.button("⊟ Heatmap",
                class  = map(m -> m == "heatmap" ? "btn active" : "btn", view_mode),
                onclick = js"() => {
                    const cur = $(view_mode)[];
                    const next = cur === 'heatmap' ? 'normal' : 'heatmap';
                    $(view_mode).notify(next);
                    const bc = document.getElementById('benchmarks-container');
                    if (bc) bc.style.display = next === 'heatmap' ? 'none' : '';
                }"),
            DOM.button("⇄ Compare",
                class  = map(m -> m == "compare" ? "btn active" : "btn", view_mode),
                onclick = js"() => {
                    const cur = $(view_mode)[];
                    const next = cur === 'compare' ? 'normal' : 'compare';
                    $(view_mode).notify(next);
                    const bc = document.getElementById('benchmarks-container');
                    if (bc) bc.style.display = next === 'compare' ? 'none' : '';
                }"),
            DOM.div(
                DOM.button("10",  class=map(m -> isnothing(m) ? "btn" : (m==10  ? "btn active" : "btn"), max_runs_obs),
                    onclick = js"() => { $(max_runs_obs).notify($(max_runs_obs)[] === 10  ? nothing : 10);  }"),
                DOM.button("25",  class=map(m -> isnothing(m) ? "btn" : (m==25  ? "btn active" : "btn"), max_runs_obs),
                    onclick = js"() => { $(max_runs_obs).notify($(max_runs_obs)[] === 25  ? nothing : 25);  }"),
                DOM.button("50",  class=map(m -> isnothing(m) ? "btn" : (m==50  ? "btn active" : "btn"), max_runs_obs),
                    onclick = js"() => { $(max_runs_obs).notify($(max_runs_obs)[] === 50  ? nothing : 50);  }"),
                DOM.button("All", class=map(m -> isnothing(m) ? "btn active" : "btn", max_runs_obs),
                    onclick = js"() => { $(max_runs_obs).notify(nothing); }"),
                class="btn-group"),
            DOM.select(
                DOM.option("All Trends", value="all"),
                DOM.option("↓ Faster",   value="faster"),
                DOM.option("↑ Slower",   value="slower"),
                DOM.option("→ Stable",   value="stable"),
                class="select-box", id="trend-select"),
            DOM.input(type="text", placeholder="Search benchmarks...",
                class="search-box", id="search-box"),
            class="controls"
        )

        csv_data   = JSON.json(data.histories)
        export_btn = DOM.button("↓ CSV",
            class   = "btn",
            onclick = Bonito.JSCode("""() => {
                const d = $csv_data;
                let c = 'Group,Benchmark,Run,Timestamp,Mean(ms),Min(ms),Median(ms),Memory,Allocs\\n';
                for(const[g,bs] of Object.entries(d))
                    for(const[b,rs] of Object.entries(bs))
                        for(const[r,v] of Object.entries(rs))
                            c+=`"\${g}","\${b}",\${r},"\${v.timestamp||''}",\${((v.mean_time_ns||0)/1e6).toFixed(3)},\${((v.min_time_ns||0)/1e6).toFixed(3)},\${((v.median_time_ns||0)/1e6).toFixed(3)},\${v.memory_bytes||0},\${v.allocs||0}\\n`;
                const a=document.createElement('a');
                a.href=URL.createObjectURL(new Blob([c],{type:'text/csv'}));
                a.download='benchmarks.csv'; a.click();
            }"""))

        outer_cls = map(dm -> dm ? "dark" : "", dark_mode)

        DOM.div(
            DOM.style(DASHBOARD_CSS),
            DOM.div(
                DOM.div(DOM.h1("BenchmarkExplorer"),
                        DOM.p("Interactive Benchmark Dashboard"),
                        class="header"),
                stats_panel,
                DOM.div(controls, export_btn),
                heatmap_dom,
                compare_dom,
                benchmarks_dom,
                DOM.div(
                    DOM.p("Generated by ", DOM.a("BenchmarkExplorer.jl", href=repo_url, target="_blank")),
                    DOM.p("hpsc lab", style="margin-top:4px"),
                    class="footer"),
                class=outer_cls
            ),
            DOM.script(client_js)
        )
    end

    Bonito.Server(app, "0.0.0.0", port)
end

function main()
    port     = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 8000
    data_dir = length(ARGS) >= 2 ? ARGS[2] : "data"
    server   = create_interactive_dashboard(data_dir; port=port)
    wait(server)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
