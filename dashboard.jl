using Pkg
using Bonito
using WGLMakie
using Dates
using Printf
using CSV
using DataFrames
using JSON
using URIs
using HTTP

Pkg.activate(@__DIR__)
include("src/HistoryManager.jl")

using .HistoryManager

function format_time_short(ns)
    if ns < 1e3
        return @sprintf("%.0f ns", ns)
    elseif ns < 1e6
        return @sprintf("%.1f μs", ns / 1e3)
    elseif ns < 1e9
        return @sprintf("%.1f ms", ns / 1e6)
    else
        return @sprintf("%.2f s", ns / 1e9)
    end
end

function format_time_ago(dt)
    if isnothing(dt)
        return "unknown"
    end
    
    diff = now() - dt
    hours = Dates.value(diff) / (1000 * 3600)
    
    if hours < 1
        mins = round(Int, hours * 60)
        return "$mins min ago"
    elseif hours < 24
        return "$(round(Int, hours)) hours ago"
    else
        days = round(Int, hours / 24)
        return "$days days ago"
    end
end

function calculate_stats(histories)
    total_benchmarks = 0
    last_run_time = nothing
    fastest_bench = ("", Inf)
    slowest_bench = ("", 0.0)
    
    for (group_name, history) in histories
        for (bench_path, runs) in history
            total_benchmarks += 1
            
            run_numbers = sort(parse.(Int, keys(runs)))
            if !isempty(run_numbers)
                latest_run = runs[string(run_numbers[end])]
                
                if haskey(latest_run, "timestamp")
                    run_time = DateTime(latest_run["timestamp"])
                    if isnothing(last_run_time) || run_time > last_run_time
                        last_run_time = run_time
                    end
                end
                
                mean_time = latest_run["mean_time_ns"]
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
        total = total_benchmarks,
        last_run = last_run_time,
        fastest = fastest_bench,
        slowest = slowest_bench
    )
end

function export_to_csv(histories, filename="benchmark_data.csv")
    rows = []
    
    for (group_name, history) in histories
        for (bench_path, runs) in history
            run_numbers = sort(parse.(Int, keys(runs)))
            for run_num in run_numbers
                data = runs[string(run_num)]
                push!(rows, (
                    group = group_name,
                    benchmark = bench_path,
                    run = run_num,
                    timestamp = data["timestamp"],
                    mean_time_ns = data["mean_time_ns"],
                    min_time_ns = data["min_time_ns"],
                    median_time_ns = data["median_time_ns"],
                    max_time_ns = data["max_time_ns"],
                    std_time_ns = data["std_time_ns"],
                    memory_bytes = data["memory_bytes"],
                    allocs = data["allocs"],
                    samples = data["samples"],
                    julia_version = get(data, "julia_version", "unknown")
                ))
            end
        end
    end
    
    df = DataFrame(rows)
    CSV.write(filename, df)
    return filename
end

function generate_history_chart_html(group_name, benchmark_path, run_number, runs)
    run_numbers = sort(parse.(Int, keys(runs)))
    
    mean_times = []
    min_times = []
    median_times = []
    max_times = []
    
    for rn in run_numbers
        data = runs[string(rn)]
        push!(mean_times, data["mean_time_ns"] / 1e6)
        push!(min_times, data["min_time_ns"] / 1e6)
        push!(median_times, data["median_time_ns"] / 1e6)
        push!(max_times, data["max_time_ns"] / 1e6)
    end
    
    labels_json = JSON.json(run_numbers)
    mean_json = JSON.json(mean_times)
    min_json = JSON.json(min_times)
    median_json = JSON.json(median_times)
    max_json = JSON.json(max_times)
    
    return """
    <h2>Performance History</h2>
    <div style="background: white; padding: 20px; border-radius: 8px; margin: 20px 0;">
        <canvas id="historyChart" style="max-height: 400px;"></canvas>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <script>
    const ctx = document.getElementById('historyChart');
    const currentRun = $run_number;
    const pointBackgroundColors = $labels_json.map(run => run === currentRun ? '#e74c3c' : undefined);
    const pointBorderColors = $labels_json.map(run => run === currentRun ? '#c0392b' : undefined);
    const pointRadius = $labels_json.map(run => run === currentRun ? 8 : 4);
    
    new Chart(ctx, {
        type: 'line',
        data: {
            labels: $labels_json,
            datasets: [
                {
                    label: 'Mean',
                    data: $mean_json,
                    borderColor: '#3498db',
                    backgroundColor: 'rgba(52, 152, 219, 0.1)',
                    borderWidth: 2,
                    pointBackgroundColor: pointBackgroundColors,
                    pointBorderColor: pointBorderColors,
                    pointRadius: pointRadius,
                    pointHoverRadius: 6,
                    tension: 0.1
                },
                {
                    label: 'Min',
                    data: $min_json,
                    borderColor: '#2ecc71',
                    backgroundColor: 'rgba(46, 204, 113, 0.1)',
                    borderWidth: 2,
                    borderDash: [5, 5],
                    pointRadius: 3,
                    pointHoverRadius: 5,
                    tension: 0.1
                },
                {
                    label: 'Median',
                    data: $median_json,
                    borderColor: '#e67e22',
                    backgroundColor: 'rgba(230, 126, 34, 0.1)',
                    borderWidth: 2,
                    borderDash: [5, 5],
                    pointRadius: 3,
                    pointHoverRadius: 5,
                    tension: 0.1
                },
                {
                    label: 'Max',
                    data: $max_json,
                    borderColor: '#95a5a6',
                    backgroundColor: 'rgba(149, 165, 166, 0.1)',
                    borderWidth: 1,
                    borderDash: [2, 2],
                    pointRadius: 2,
                    pointHoverRadius: 4,
                    tension: 0.1
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
                title: {
                    display: true,
                    text: 'All Runs - Current Run Highlighted in Red',
                    font: { size: 16, weight: 'bold' }
                },
                legend: {
                    display: true,
                    position: 'top'
                },
                tooltip: {
                    mode: 'index',
                    intersect: false,
                    callbacks: {
                        label: function(context) {
                            let label = context.dataset.label || '';
                            if (label) {
                                label += ': ';
                            }
                            label += context.parsed.y.toFixed(3) + ' ms';
                            if (context.parsed.x + 1 === currentRun) {
                                label += ' (Current)';
                            }
                            return label;
                        }
                    }
                }
            },
            scales: {
                x: {
                    title: { display: true, text: 'Run Number', font: { weight: 'bold' } },
                    grid: { color: 'rgba(0, 0, 0, 0.05)' }
                },
                y: {
                    title: { display: true, text: 'Time (ms)', font: { weight: 'bold' } },
                    beginAtZero: false,
                    grid: { color: 'rgba(0, 0, 0, 0.05)' }
                }
            },
            interaction: { mode: 'nearest', axis: 'x', intersect: false }
        }
    });
    </script>
    """
end

function create_benchmark_plot(timestamps, mean_times, min_times, median_times, memory, allocs, title, 
                              show_mean, show_min, show_median, show_percentage, dark_mode,
                              group_name, benchmark_path, port)
    run_numbers = collect(1:length(timestamps))
    
    mean_data = @lift begin
        if $show_percentage && length(mean_times) > 0
            baseline = mean_times[1]
            [(t / baseline - 1.0) * 100.0 for t in mean_times]
        else
            mean_times ./ 1e6
        end
    end
    
    min_data = @lift begin
        if $show_percentage && length(min_times) > 0
            baseline = min_times[1]
            [(t / baseline - 1.0) * 100.0 for t in min_times]
        else
            min_times ./ 1e6
        end
    end
    
    median_data = @lift begin
        if $show_percentage && length(median_times) > 0
            baseline = median_times[1]
            [(t / baseline - 1.0) * 100.0 for t in median_times]
        else
            median_times ./ 1e6
        end
    end
    
    ylabel = @lift $show_percentage ? "% change" : "time (ms)"
    
    bg_color = @lift $dark_mode ? :black : :white
    text_color = @lift $dark_mode ? :white : :black
    grid_color = @lift $dark_mode ? (:white, 0.1) : (:black, 0.1)
    
    fig = Figure(size=(350, 300), backgroundcolor=bg_color)
    ax = Axis(fig[1, 1], 
              xlabel="run number",
              ylabel=ylabel,
              title=title,
              backgroundcolor=bg_color,
              xgridcolor=grid_color,
              ygridcolor=grid_color,
              xlabelcolor=text_color,
              ylabelcolor=text_color,
              titlecolor=text_color,
              xticklabelcolor=text_color,
              yticklabelcolor=text_color,
              leftspinecolor=text_color,
              rightspinecolor=text_color,
              topspinecolor=text_color,
              bottomspinecolor=text_color)
    
    lines!(ax, run_numbers, mean_data, color=:blue, linewidth=2, visible=show_mean)
    lines!(ax, run_numbers, min_data, color=:green, linewidth=2, visible=show_min)
    lines!(ax, run_numbers, median_data, color=:orange, linewidth=2, visible=show_median)
    
    scatter!(ax, run_numbers, mean_data, color=:blue, markersize=10, marker=:circle, visible=show_mean)
    scatter!(ax, run_numbers, min_data, color=:green, markersize=10, marker=:circle, visible=show_min)
    scatter!(ax, run_numbers, median_data, color=:orange, markersize=10, marker=:circle, visible=show_median)
    
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
                catch e
                    @warn "Could not auto-open browser. Please visit: $detail_url"
                end
            end
        end
    end
    
    tooltip_visible = Observable(false)
    
    text!(ax, 0.5, 0.95, 
          text=@lift($tooltip_visible ? "Click point to see details" : ""),
          align=(:center, :top),
          space=:relative,
          fontsize=12,
          color=@lift($dark_mode ? :white : :black),
          strokecolor=@lift($dark_mode ? :black : :white),
          strokewidth=1)
    
    on(events(fig).mouseposition) do mp
        plt = mouseposition(ax.scene)
        
        near_point = false
        for (i, rn) in enumerate(run_numbers)
            if show_mean[]
                dx = plt[1] - rn
                dy = plt[2] - mean_data[][i]
                dist = sqrt(dx^2 + dy^2)
                if dist < 1.5
                    near_point = true
                    break
                end
            end
            if !near_point && show_min[]
                dx = plt[1] - rn
                dy = plt[2] - min_data[][i]
                dist = sqrt(dx^2 + dy^2)
                if dist < 1.5
                    near_point = true
                    break
                end
            end
            if !near_point && show_median[]
                dx = plt[1] - rn
                dy = plt[2] - median_data[][i]
                dist = sqrt(dx^2 + dy^2)
                if dist < 1.5
                    near_point = true
                    break
                end
            end
        end
        
        tooltip_visible[] = near_point
    end
    
    hlines!(ax, [0.0], color=:gray, linestyle=:dash, linewidth=1, visible=show_percentage)
    
    on(show_percentage) do is_pct
        if is_pct
            all_pct_data = Float64[]
            if show_mean[]
                append!(all_pct_data, mean_data[])
            end
            if show_min[]
                append!(all_pct_data, min_data[])
            end
            if show_median[]
                append!(all_pct_data, median_data[])
            end
            
            if !isempty(all_pct_data)
                min_val = minimum(all_pct_data)
                max_val = maximum(all_pct_data)
                margin = (max_val - min_val) * 0.1
                ylims!(ax, min_val - margin, max_val + margin)
            end
        else
            autolimits!(ax)
        end
    end
    
    for obs in [show_mean, show_min, show_median]
        on(obs) do _
            if show_percentage[]
                all_pct_data = Float64[]
                if show_mean[]
                    append!(all_pct_data, mean_data[])
                end
                if show_min[]
                    append!(all_pct_data, min_data[])
                end
                if show_median[]
                    append!(all_pct_data, median_data[])
                end
                
                if !isempty(all_pct_data)
                    min_val = minimum(all_pct_data)
                    max_val = maximum(all_pct_data)
                    margin = (max_val - min_val) * 0.1
                    ylims!(ax, min_val - margin, max_val + margin)
                end
            end
        end
    end
    
    return fig
end

function create_benchmark_row(history, benchmark_name, show_mean, show_min, show_median, show_percentage, dark_mode, group_name, port)
    subbench_names = get_subbenchmark_names(history, benchmark_name)
    
    plots = []
    for subbench_name in subbench_names
        try
            timestamps, mean_times, min_times, median_times, memory, allocs = 
                extract_timeseries_with_timestamps(history, benchmark_name, subbench_name)
            
            parts = split(subbench_name, "/")
            if length(parts) >= 2
                filename = replace(parts[end-1], "elixir_" => "", ".jl" => "")
                metric = parts[end]
                title = "$filename/$metric"
            else
                title = subbench_name
            end
            
            fig = create_benchmark_plot(timestamps, mean_times, min_times, median_times, 
                                        memory, allocs, title,
                                        show_mean, show_min, show_median, show_percentage, dark_mode,
                                        group_name, subbench_name, port)
            push!(plots, fig)
        catch e
            @warn "Failed to create plot for $benchmark_name/$subbench_name" exception=e
        end
    end
    
    return plots
end

function create_group_section(session, group_name, history, show_mean, show_min, show_median, show_percentage, dark_mode, group_visible, port)
    
    benchmark_names = get_benchmark_names(history)
    
    if isempty(benchmark_names)
        return DOM.div()
    end
    
    group_header = DOM.div(
        DOM.h1("$group_name Benchmarks ($(length(benchmark_names)))", 
               style="text-align: center; color: #2c3e50; margin: 40px 0 20px 0; padding-bottom: 10px; border-bottom: 3px solid #3498db;"),
        DOM.hr(style="border: 1px solid #ecf0f1; margin: 20px 0;"),
        style=@lift($group_visible ? "display: block;" : "display: none;")
    )
    
    all_benchmarks = []
    
    for benchmark_name in benchmark_names
        bench_title = DOM.h2(benchmark_name, 
                             style="color: #34495e; margin-top: 30px; margin-bottom: 15px;")
        push!(all_benchmarks, bench_title)
        
        plots = create_benchmark_row(history, benchmark_name, show_mean, show_min, show_median, show_percentage, dark_mode, group_name, port)
        
        if !isempty(plots)
            n_plots = length(plots)
            cols = min(n_plots, 4)
            
            plots_row = DOM.div(
                [plot for plot in plots]...,
                style="display: grid; grid-template-columns: repeat($cols, 1fr); gap: 15px; margin-bottom: 30px;"
            )
            
            push!(all_benchmarks, plots_row)
        end
        
        push!(all_benchmarks, DOM.hr(style="border: 1px solid #ecf0f1; margin: 30px 0;"))
    end
    
    return DOM.div(
        group_header,
        DOM.div(all_benchmarks..., style=@lift($group_visible ? "display: block;" : "display: none;"))
    )
end

function start_dashboard(; port=8000)
    history_files = [
        ("Trixi", "data/history_trixi.json"),
        ("Enzyme", "data/history_enzyme.json"),
        ("Trixi", "data/history.json")
    ]
    
    histories = Dict{String, Any}()
    
    for (name, file) in history_files
        if isfile(file) && !haskey(histories, name)
            try
                histories[name] = load_history(file)
            catch e
                @warn "Failed to load $file" exception=e
            end
        end
    end
    
    if isempty(histories)
        @error "No history files found!"
        return
    end
    
    csv_filename = joinpath(@__DIR__, "data", "benchmark_export.csv")
    try
        export_to_csv(histories, csv_filename)
    catch e
        @warn "Failed to export CSV" exception=e
    end
    
    app = App() do session
        show_mean = Observable(true)
        show_min = Observable(true)
        show_median = Observable(true)
        show_percentage = Observable(false)
        dark_mode = Observable(false)
        
        group_visibility = Dict{String, Observable{Bool}}()
        for group_name in keys(histories)
            group_visibility[group_name] = Observable(true)
        end
        
        stats = calculate_stats(histories)
        
        main_header = DOM.div(
            DOM.h1("Benchmark Dashboard", 
                   style="text-align: center; color: #2c3e50; margin: 20px 0; font-size: 2.5em;"),
            DOM.hr(style="border: 2px solid #3498db; margin: 20px 0;")
        )
        
        stats_panel = DOM.div(
            DOM.div(
                DOM.div(
                    DOM.div(
                        DOM.span("Total", style="font-weight: bold; color: white; font-size: 0.9em;"),
                        DOM.br(),
                        DOM.span("$(stats.total)", style="font-size: 2.5em; color: white; font-weight: bold;"),
                        DOM.br(),
                        DOM.span("benchmarks", style="font-size: 0.8em; color: rgba(255,255,255,0.8);"),
                        style="text-align: center; padding: 20px;"
                    ),
                    DOM.div(
                        DOM.span("Last Run", style="font-weight: bold; color: white; font-size: 0.9em;"),
                        DOM.br(),
                        DOM.span(format_time_ago(stats.last_run), style="font-size: 1.8em; color: white; font-weight: bold;"),
                        style="text-align: center; padding: 20px;"
                    ),
                    style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;"
                ),
                DOM.div(
                    DOM.div(
                        DOM.span("Fastest", style="font-weight: bold; color: white; font-size: 0.9em;"),
                        DOM.br(),
                        DOM.span(format_time_short(stats.fastest[2]), style="font-size: 1.5em; color: #2ecc71; font-weight: bold;"),
                        DOM.br(),
                        DOM.span(last(split(stats.fastest[1], "/")), style="font-size: 0.7em; color: rgba(255,255,255,0.7);"),
                        style="text-align: center; padding: 20px;"
                    ),
                    DOM.div(
                        DOM.span("Slowest", style="font-weight: bold; color: white; font-size: 0.9em;"),
                        DOM.br(),
                        DOM.span(format_time_short(stats.slowest[2]), style="font-size: 1.5em; color: #e74c3c; font-weight: bold;"),
                        DOM.br(),
                        DOM.span(last(split(stats.slowest[1], "/")), style="font-size: 0.7em; color: rgba(255,255,255,0.7);"),
                        style="text-align: center; padding: 20px;"
                    ),
                    style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-top: 20px;"
                ),
                style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; border-radius: 12px; margin-bottom: 30px; box-shadow: 0 10px 25px rgba(0,0,0,0.2);"
            )
        )
        
        mean_check = Bonito.Checkbox(true)
        min_check = Bonito.Checkbox(true)
        median_check = Bonito.Checkbox(true)
        percentage_check = Bonito.Checkbox(false)
        dark_mode_check = Bonito.Checkbox(false)
        
        on(session, mean_check.value) do val
            show_mean[] = val
        end
        
        on(session, min_check.value) do val
            show_min[] = val
        end
        
        on(session, median_check.value) do val
            show_median[] = val
        end
        
        on(session, percentage_check.value) do val
            show_percentage[] = val
        end
        
        on(session, dark_mode_check.value) do val
            dark_mode[] = val
        end
        
        group_checks = []
        for group_name in sort(collect(keys(histories)))
            group_check = Bonito.Checkbox(true)
            on(session, group_check.value) do val
                group_visibility[group_name][] = val
            end
            
            check_label = DOM.label(
                group_check,
                " $group_name",
                style="color: #2980b9; font-weight: bold; margin-right: 20px; cursor: pointer; font-size: 1.1em;"
            )
            push!(group_checks, check_label)
        end
        
        csv_button = DOM.a("Download CSV",
            href="data/benchmark_export.csv",
            download="benchmark_data.csv",
            target="_blank",
            style="background-color: #27ae60; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; font-size: 1em; font-weight: bold; margin-left: 20px; text-decoration: none; display: inline-block;"
        )
        
        controls = DOM.div(
            DOM.h3("Display Options", style="color: #2c3e50; margin-bottom: 15px;"),
            
            DOM.div(
                DOM.label(mean_check, " Mean", style="color: #3498db; font-weight: bold; margin-right: 20px; cursor: pointer; font-size: 1.1em;"),
                DOM.label(min_check, " Min", style="color: #2ecc71; font-weight: bold; margin-right: 20px; cursor: pointer; font-size: 1.1em;"),
                DOM.label(median_check, " Median", style="color: #e67e22; font-weight: bold; cursor: pointer; font-size: 1.1em;"),
            ),
            
            DOM.hr(style="border: 1px solid #bdc3c7; margin: 15px 0;"),
            
            DOM.div(
                DOM.label(percentage_check, " Show as % change from first run", style="color: #8e44ad; font-weight: bold; cursor: pointer; font-size: 1.1em; margin-right: 20px;"),
                DOM.label(dark_mode_check, " Dark Mode", style="color: #34495e; font-weight: bold; cursor: pointer; font-size: 1.1em;"),
            ),
            
            DOM.hr(style="border: 1px solid #bdc3c7; margin: 15px 0;"),
            
            DOM.div(
                DOM.span("Show Groups: ", style="color: #2c3e50; font-weight: bold; font-size: 1.1em; margin-right: 10px;"),
                group_checks...,
                csv_button
            ),
            
            style="background-color: #ecf0f1; padding: 20px; border-radius: 8px; margin-bottom: 30px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);"
        )
        
        all_sections = []
        
        sorted_group_names = sort(collect(keys(histories)))
        
        for (idx, group_name) in enumerate(sorted_group_names)
            history = histories[group_name]
            section = create_group_section(session, group_name, history, show_mean, show_min, show_median, 
                                          show_percentage, dark_mode, group_visibility[group_name], port)
            push!(all_sections, section)
            
            if idx < length(sorted_group_names)
                push!(all_sections, DOM.div(
                    style="height: 40px; background: linear-gradient(to bottom, #ecf0f1, transparent); margin: 40px 0;"
                ))
            end
        end
        
        footer = DOM.div(
            DOM.hr(style="border: 1px solid #bdc3c7; margin: 40px 0;"),
            DOM.p(
                "Loaded $(length(histories)) group$(length(histories) > 1 ? "s" : ""): $(join(sorted_group_names, ", "))",
                style="text-align: center; color: #95a5a6; font-size: 0.9em;"
            ),
            DOM.p(
                "Last updated: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))",
                style="text-align: center; color: #95a5a6; font-size: 0.9em;"
            )
        )
        
        return DOM.div(
            main_header,
            stats_panel,
            controls,
            DOM.div(all_sections...),
            footer,
            style="font-family: Arial, sans-serif; padding: 30px; max-width: 1600px; margin: auto; background-color: #f8f9fa; min-height: 100vh;"
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
                        
                        mean_ms = data["mean_time_ns"] / 1e6
                        min_ms = data["min_time_ns"] / 1e6
                        median_ms = data["median_time_ns"] / 1e6
                        max_ms = data["max_time_ns"] / 1e6
                        memory_mb = data["memory_bytes"] / (1024 * 1024)
                        
                        chart_html = generate_history_chart_html(group_name, benchmark_path, run_number, runs)
                        
                        detail_html = """
                        <!DOCTYPE html>
                        <html>
                        <head>
                            <title>Benchmark Details - Run #$run_number</title>
                            <meta charset="utf-8">
                            <style>
                                body { font-family: Arial, sans-serif; padding: 30px; background: #f8f9fa; margin: 0; }
                                .container { max-width: 1200px; margin: auto; background: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                                h1 { color: #2c3e50; margin-bottom: 10px; }
                                .subtitle { color: #7f8c8d; font-size: 1.1em; margin-bottom: 30px; }
                                hr { border: 2px solid #3498db; margin: 20px 0; }
                                h2 { color: #2c3e50; margin-top: 30px; border-bottom: 2px solid #ecf0f1; padding-bottom: 10px; }
                                .stats-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin: 20px 0; }
                                .stat-box { background: #ecf0f1; padding: 20px; border-radius: 8px; text-align: center; }
                                .stat-label { font-weight: bold; font-size: 0.9em; color: #7f8c8d; margin-bottom: 10px; }
                                .stat-value { font-size: 2em; font-weight: bold; color: #2c3e50; }
                                .stat-value.blue { color: #3498db; }
                                .stat-value.orange { color: #e67e22; }
                                .stat-value.green { color: #2ecc71; }
                                .stat-value.red { color: #e74c3c; }
                                .stat-value.purple { color: #9b59b6; }
                                .stat-value.teal { color: #16a085; }
                                code { background: #ecf0f1; padding: 2px 8px; border-radius: 3px; font-family: monospace; }
                                table { width: 100%; border-collapse: collapse; margin: 20px 0; background: #f8f9fa; }
                                td { padding: 12px; border-bottom: 1px solid #ecf0f1; }
                                td:first-child { font-weight: bold; width: 200px; }
                                button { background: #3498db; color: white; border: none; padding: 12px 24px; border-radius: 5px; cursor: pointer; font-size: 16px; font-weight: bold; }
                                button:hover { background: #2980b9; }
                                pre { background: #2c3e50; color: #ecf0f1; padding: 20px; border-radius: 8px; overflow-x: auto; font-size: 0.9em; }
                                @media (max-width: 768px) { .stats-grid { grid-template-columns: repeat(2, 1fr); } }
                            </style>
                        </head>
                        <body>
                            <div class="container">
                                <h1>Benchmark Details</h1>
                                <div class="subtitle">Group: <strong>$group_name</strong> | Run #<strong>$run_number</strong></div>
                                <hr>
                                
                                <h2>Benchmark Path</h2>
                                <code>$benchmark_path</code>
                                
                                <h2>Timing Statistics</h2>
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
                                
                                <h2>Memory Usage</h2>
                                <div class="stats-grid" style="grid-template-columns: repeat(2, 1fr);">
                                    <div class="stat-box">
                                        <div class="stat-label">Total Memory</div>
                                        <div class="stat-value purple">$(@sprintf("%.2f", memory_mb)) MB</div>
                                    </div>
                                    <div class="stat-box">
                                        <div class="stat-label">Allocations</div>
                                        <div class="stat-value teal">$(data["allocs"])</div>
                                    </div>
                                </div>
                                
                                <h2>Run Metadata</h2>
                                <table>
                                    <tr>
                                        <td>Timestamp</td>
                                        <td>$(data["timestamp"])</td>
                                    </tr>
                                    <tr>
                                        <td>Samples</td>
                                        <td>$(data["samples"])</td>
                                    </tr>
                                    <tr>
                                        <td>Julia Version</td>
                                        <td>$(get(data, "julia_version", "unknown"))</td>
                                    </tr>
                                </table>
                                
                                $chart_html
                                
                                <h2>Raw Data (JSON)</h2>
                                <pre>$(JSON.json(data, 2))</pre>
                                
                                <br>
                                <button onclick="window.close()">Close Window</button>
                            </div>
                        </body>
                        </html>
                        """
                        
                        return HTTP.Response(200, ["Content-Type" => "text/html"], detail_html)
                    end
                end
                
                return HTTP.Response(404, ["Content-Type" => "text/html"], "<h1>404 - Not Found</h1>")
            catch e
                return HTTP.Response(500, ["Content-Type" => "text/html"], "<h1>500 - Error</h1>")
            end
        end
        
        return HTTP.Response(404, ["Content-Type" => "text/html"], "<h1>404 - Not Found</h1>")
    end)
    
    println("Dashboard URL: http://localhost:$port")
    
    try
        wait(server)
    catch e
        if !isa(e, InterruptException)
            rethrow(e)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    port = length(ARGS) > 0 ? parse(Int, ARGS[1]) : 8000
    start_dashboard(port=port)
end