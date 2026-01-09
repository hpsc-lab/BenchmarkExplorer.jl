using Pkg
Pkg.activate(@__DIR__)

using Bonito
using WGLMakie
using Dates
using Printf
using JSON

include("src/BenchmarkUI.jl")
using .BenchmarkUI

function create_interactive_dashboard(data_dir="data"; port=8000)
    data = load_dashboard_data(data_dir)

    app = App() do session
        show_mean = Observable(true)
        show_min = Observable(false)
        show_median = Observable(false)
        show_percentage = Observable(false)
        dark_mode = Observable(false)

        group_visibility = Dict(g => Observable(true) for g in data.groups)

        stats_text = Observable("")

        function update_stats()
            bg = dark_mode[] ? "#2c3e50" : "#ecf0f1"
            color = dark_mode[] ? "#ecf0f1" : "#2c3e50"
            accent = dark_mode[] ? "#3498db" : "#2980b9"

            total_bench = data.stats.total_benchmarks
            total_r = data.stats.total_runs
            fastest_time = format_time_short(data.stats.fastest[2])
            slowest_time = format_time_short(data.stats.slowest[2])

            stats_text[] = """
            <div style="background: $bg; padding: 20px; border-radius: 8px; margin: 20px 0;">
                <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px;">
                    <div style="text-align: center;">
                        <div style="font-size: 2em; font-weight: bold; color: $accent;">$total_bench</div>
                        <div style="color: $color; font-size: 0.9em;">Total Benchmarks</div>
                    </div>
                    <div style="text-align: center;">
                        <div style="font-size: 2em; font-weight: bold; color: $accent;">$total_r</div>
                        <div style="color: $color; font-size: 0.9em;">Total Runs</div>
                    </div>
                    <div style="text-align: center;">
                        <div style="font-size: 1.5em; font-weight: bold; color: #27ae60;">$fastest_time</div>
                        <div style="color: $color; font-size: 0.9em;">Fastest</div>
                    </div>
                    <div style="text-align: center;">
                        <div style="font-size: 1.5em; font-weight: bold; color: #e74c3c;">$slowest_time</div>
                        <div style="color: $color; font-size: 0.9em;">Slowest</div>
                    </div>
                </div>
            </div>
            """
        end

        update_stats()

        on(dark_mode) do _
            update_stats()
        end

        figure_data = []

        for group_name in data.groups
            history = data.histories[group_name]
            benchmark_groups = get_benchmark_groups(history)

            for (subgroup, benchmarks) in sort(collect(benchmark_groups))
                fig = Figure(size=(1400, 500))
                ax = Axis(fig[1, 1],
                    title="$group_name - $subgroup",
                    xlabel="Commit",
                    ylabel="Time (ms)")

                colors = Makie.wong_colors()

                first_plot_data = prepare_plot_data(history, benchmarks[1];
                    metric=show_mean[] ? :mean : (show_min[] ? :min : :median),
                    as_percentage=show_percentage[])

                commit_map = Dict(i => format_commit_hash(h) for (i, h) in enumerate(first_plot_data.commit_hashes))

                for (idx, benchmark_path) in enumerate(benchmarks)
                    plot_data = prepare_plot_data(history, benchmark_path;
                        metric=show_mean[] ? :mean : (show_min[] ? :min : :median),
                        as_percentage=show_percentage[])

                    if !isempty(plot_data.y)
                        color = colors[mod1(idx, length(colors))]
                        x_values = collect(1:length(plot_data.y))
                        lines!(ax, x_values, plot_data.y,
                            label=benchmark_path,
                            color=color,
                            linewidth=2)
                        scatter!(ax, x_values, plot_data.y,
                            color=color,
                            markersize=8,
                            marker=:circle,
                            inspector_label = (self, i, p) -> begin
                                idx = round(Int, p[1])
                                if idx >= 1 && idx <= length(plot_data.commit_hashes)
                                    """
                                    Benchmark: $benchmark_path
                                    Commit: $(plot_data.commit_hashes[idx])
                                    Time: $(round(p[2], digits=3)) $(show_percentage[] ? "%" : "ms")
                                    Mean: $(round(plot_data.mean[idx], digits=3)) ms
                                    Median: $(round(plot_data.median[idx], digits=3)) ms
                                    Min: $(round(plot_data.min[idx], digits=3)) ms
                                    Max: $(round(plot_data.max[idx], digits=3)) ms
                                    Memory: $(format_memory(plot_data.memory[idx]))
                                    Allocs: $(plot_data.allocs[idx])
                                    Julia: $(plot_data.julia_versions[idx])
                                    Date: $(plot_data.timestamps[idx])
                                    """
                                else
                                    "Point #$idx"
                                end
                            end)
                    end
                end

                if !isempty(first_plot_data.commit_hashes)
                    x_indices = collect(1:length(first_plot_data.commit_hashes))
                    commit_labels = [format_commit_hash(h) for h in first_plot_data.commit_hashes]
                    ax.xticks = (x_indices, commit_labels)
                    ax.xticklabelrotation = π/4
                end

                DataInspector(fig)
                axislegend(ax, position=:lt)

                on(show_mean) do _
                    empty!(ax)
                    local temp_plot_data = nothing
                    for (idx, benchmark_path) in enumerate(benchmarks)
                        plot_data = prepare_plot_data(history, benchmark_path;
                            metric=show_mean[] ? :mean : (show_min[] ? :min : :median),
                            as_percentage=show_percentage[])
                        if idx == 1
                            temp_plot_data = plot_data
                        end
                        if !isempty(plot_data.y)
                            color = colors[mod1(idx, length(colors))]
                            x_values = collect(1:length(plot_data.y))
                            lines!(ax, x_values, plot_data.y,
                                label=benchmark_path,
                                color=color,
                                linewidth=2)
                            scatter!(ax, x_values, plot_data.y,
                                color=color,
                                markersize=8,
                                marker=:circle,
                                inspector_label = (self, i, p) -> begin
                                    idx = round(Int, p[1])
                                    if idx >= 1 && idx <= length(plot_data.commit_hashes)
                                        """
                                        Benchmark: $benchmark_path
                                        Commit: $(plot_data.commit_hashes[idx])
                                        Time: $(round(p[2], digits=3)) $(show_percentage[] ? "%" : "ms")
                                        Mean: $(round(plot_data.mean[idx], digits=3)) ms
                                        Median: $(round(plot_data.median[idx], digits=3)) ms
                                        Min: $(round(plot_data.min[idx], digits=3)) ms
                                        Max: $(round(plot_data.max[idx], digits=3)) ms
                                        Memory: $(format_memory(plot_data.memory[idx]))
                                        Allocs: $(plot_data.allocs[idx])
                                        Julia: $(plot_data.julia_versions[idx])
                                        Date: $(plot_data.timestamps[idx])
                                        """
                                    else
                                        "Point #$idx"
                                    end
                                end)
                        end
                    end
                    if !isnothing(temp_plot_data) && !isempty(temp_plot_data.commit_hashes)
                        x_indices = collect(1:length(temp_plot_data.commit_hashes))
                        commit_labels = [format_commit_hash(h) for h in temp_plot_data.commit_hashes]
                        ax.xticks = (x_indices, commit_labels)
                    end
                    axislegend(ax, position=:lt)
                end

                on(show_percentage) do _
                    empty!(ax)
                    ax.ylabel = show_percentage[] ? "Change (%)" : "Time (ms)"
                    local temp_plot_data = nothing
                    for (idx, benchmark_path) in enumerate(benchmarks)
                        plot_data = prepare_plot_data(history, benchmark_path;
                            metric=show_mean[] ? :mean : (show_min[] ? :min : :median),
                            as_percentage=show_percentage[])
                        if idx == 1
                            temp_plot_data = plot_data
                        end
                        if !isempty(plot_data.y)
                            color = colors[mod1(idx, length(colors))]
                            x_values = collect(1:length(plot_data.y))
                            lines!(ax, x_values, plot_data.y,
                                label=benchmark_path,
                                color=color,
                                linewidth=2)
                            scatter!(ax, x_values, plot_data.y,
                                color=color,
                                markersize=8,
                                marker=:circle,
                                inspector_label = (self, i, p) -> begin
                                    idx = round(Int, p[1])
                                    if idx >= 1 && idx <= length(plot_data.commit_hashes)
                                        """
                                        Benchmark: $benchmark_path
                                        Commit: $(plot_data.commit_hashes[idx])
                                        Time: $(round(p[2], digits=3)) $(show_percentage[] ? "%" : "ms")
                                        Mean: $(round(plot_data.mean[idx], digits=3)) ms
                                        Median: $(round(plot_data.median[idx], digits=3)) ms
                                        Min: $(round(plot_data.min[idx], digits=3)) ms
                                        Max: $(round(plot_data.max[idx], digits=3)) ms
                                        Memory: $(format_memory(plot_data.memory[idx]))
                                        Allocs: $(plot_data.allocs[idx])
                                        Julia: $(plot_data.julia_versions[idx])
                                        Date: $(plot_data.timestamps[idx])
                                        """
                                    else
                                        "Point #$idx"
                                    end
                                end)
                        end
                    end
                    if !isnothing(temp_plot_data) && !isempty(temp_plot_data.commit_hashes)
                        x_indices = collect(1:length(temp_plot_data.commit_hashes))
                        commit_labels = [format_commit_hash(h) for h in temp_plot_data.commit_hashes]
                        ax.xticks = (x_indices, commit_labels)
                    end
                    axislegend(ax, position=:lt)
                end

                on(dark_mode) do is_dark
                    if is_dark
                        ax.backgroundcolor = :gray20
                        ax.xgridcolor = :gray40
                        ax.ygridcolor = :gray40
                    else
                        ax.backgroundcolor = :white
                        ax.xgridcolor = :gray80
                        ax.ygridcolor = :gray80
                    end
                end

                fig_info = (
                    group=group_name,
                    subgroup=subgroup,
                    benchmarks=benchmarks,
                    fig=fig,
                    visibility=group_visibility[group_name]
                )
                push!(figure_data, fig_info)
            end
        end

        figures = map(group_visibility[data.groups[1]], (g -> group_visibility[g] for g in data.groups[2:end])...) do _...
            containers = []

            for fig_info in figure_data
                if !fig_info.visibility[]
                    continue
                end

                push!(containers, DOM.div(fig_info.fig, style="margin: 20px 0;"))
            end

            if isempty(containers)
                return DOM.div(
                    DOM.h2("No benchmarks visible", style="text-align: center; color: #6c757d; margin: 40px 0;"),
                    DOM.p("Enable groups using toggles above", style="text-align: center; color: #95a5a6;")
                )
            end

            return DOM.div(containers...)
        end

        mean_check = Bonito.Checkbox(show_mean, Dict{Symbol, Any}())
        min_check = Bonito.Checkbox(show_min, Dict{Symbol, Any}())
        median_check = Bonito.Checkbox(show_median, Dict{Symbol, Any}())
        percentage_check = Bonito.Checkbox(show_percentage, Dict{Symbol, Any}())
        dark_mode_check = Bonito.Checkbox(dark_mode, Dict{Symbol, Any}())

        search_info = DOM.p(
            "Use group toggles below to filter benchmarks. Full search available in exported HTML.",
            style="font-size: 0.9em; color: #6c757d; font-style: italic; margin: 10px 0;"
        )

        csv_data_json = JSON.json(data.histories)
        export_button = DOM.button(
            "📥 Export CSV",
            onclick=Bonito.JSCode("""
                (e) => {
                    const data = $csv_data_json;
                    let csv = 'Group,Benchmark,Run,Timestamp,Mean (ms),Min (ms),Median (ms),Memory (bytes),Allocations\\n';

                    for (const [group, benchmarks] of Object.entries(data)) {
                        for (const [benchmark, runs] of Object.entries(benchmarks)) {
                            const runNumbers = Object.keys(runs).sort((a, b) => parseInt(a) - parseInt(b));
                            for (const runNum of runNumbers) {
                                const run = runs[runNum];
                                const timestamp = run.timestamp || '';
                                const mean = (run.mean_time_ns || 0) / 1e6;
                                const min = (run.min_time_ns || 0) / 1e6;
                                const median = (run.median_time_ns || 0) / 1e6;
                                const memory = run.memory_bytes || 0;
                                const allocs = run.allocs || 0;
                                csv += `"\${group}","\${benchmark}",\${runNum},"\${timestamp}",\${mean.toFixed(3)},\${min.toFixed(3)},\${median.toFixed(3)},\${memory},\${allocs}\\n`;
                            }
                        }
                    }

                    const blob = new Blob([csv], { type: 'text/csv' });
                    const url = window.URL.createObjectURL(blob);
                    const a = document.createElement('a');
                    a.href = url;
                    a.download = 'benchmarks.csv';
                    a.click();
                    window.URL.revokeObjectURL(url);
                }
            """),
            style="""
                padding: 10px 20px;
                background: #48bb78;
                color: white;
                border: none;
                border-radius: 6px;
                cursor: pointer;
                font-size: 14px;
                font-weight: 600;
                transition: all 0.2s;
                margin: 10px 0;
            """
        )

        group_checks = []
        for group_name in data.groups
            check = Bonito.Checkbox(group_visibility[group_name], Dict{Symbol, Any}())
            push!(group_checks,
                DOM.label(check, " $group_name",
                    style="margin-right: 15px; cursor: pointer; font-weight: bold;"))
        end

        controls = DOM.div(
            DOM.h3("Controls", style="color: #2c3e50; margin-bottom: 15px;"),
            DOM.div(
                DOM.label(mean_check, " Mean", style="margin-right: 15px; cursor: pointer;"),
                DOM.label(min_check, " Min", style="margin-right: 15px; cursor: pointer;"),
                DOM.label(median_check, " Median", style="margin-right: 15px; cursor: pointer;"),
                DOM.label(percentage_check, " % Change", style="margin-right: 15px; cursor: pointer;"),
                DOM.label(dark_mode_check, " Dark Mode", style="margin-right: 15px; cursor: pointer;"),
                export_button,
            ),
            DOM.hr(),
            DOM.div(
                DOM.span("Groups: ", style="font-weight: bold; margin-right: 10px;"),
                group_checks...
            ),
            search_info,
            style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 20px 0;"
        )

        header = DOM.div(
            DOM.h1("📊 BenchmarkExplorer.jl",
                style="font-size: 3em; margin-bottom: 10px; color: white; text-shadow: 2px 2px 4px rgba(0,0,0,0.2);"),
            DOM.p("Interactive Benchmark Dashboard • Real-time visualization",
                style="font-size: 1.2em; opacity: 0.9; color: white;"),
            style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; text-align: center; margin: -30px -30px 20px -30px; border-radius: 20px 20px 0 0;"
        )

        stats_panel = DOM.div(
            Bonito.jsrender(session, stats_text),
            style="margin: 20px 0;"
        )

        footer = DOM.div(
            DOM.p(
                "Generated by BenchmarkExplorer.jl • Powered by Bonito.jl + WGLMakie.jl",
                style="text-align: center; color: white; margin: 0;"
            ),
            DOM.p(
                "Last updated: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))",
                style="text-align: center; color: white; font-size: 0.9em; opacity: 0.8; margin-top: 10px;"
            ),
            style="background: #2c3e50; color: white; padding: 20px; margin: 30px -30px -30px -30px; border-radius: 0 0 20px 20px;"
        )

        return DOM.div(
            DOM.div(
                header,
                stats_panel,
                controls,
                Bonito.jsrender(session, figures),
                footer,
                style="background: white; border-radius: 20px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); overflow: hidden;"
            ),
            style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif; padding: 30px; max-width: 1600px; margin: auto; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh;"
        )
    end

    println("Starting Bonito server on http://0.0.0.0:$port")
    server = Bonito.Server(app, "0.0.0.0", port)

    return server
end

function main()
    port = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 8000
    data_dir = length(ARGS) >= 2 ? ARGS[2] : "data"

    server = create_interactive_dashboard(data_dir; port=port)

    println("Dashboard running at http://localhost:$port")
    println("Press Ctrl+C to stop")

    wait(server)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
