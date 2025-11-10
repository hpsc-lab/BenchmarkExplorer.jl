using Pkg
using Bonito
using WGLMakie
using Dates
using Printf

Pkg.activate(@__DIR__)
include("src/HistoryManager.jl")

using .HistoryManager

function create_benchmark_plot(timestamps, mean_times, min_times, median_times, memory, allocs, title)
    run_numbers = collect(1:length(timestamps))
    
    mean_ms = mean_times ./ 1e6
    min_ms = min_times ./ 1e6
    median_ms = median_times ./ 1e6
    
    fig = Figure(size=(350, 300))
    ax = Axis(fig[1, 1], 
              xlabel="run Number",
              ylabel="time (ms)",
              title=title)
    
    lines!(ax, run_numbers, mean_ms, color=:blue, linewidth=2, label="Mean")
    scatter!(ax, run_numbers, mean_ms, 
            color=:blue, 
            markersize=10,
            marker=:circle,
            inspector_label = (self, i, p) -> "soon")
    
    lines!(ax, run_numbers, min_ms, color=:green, linewidth=2, label="Min")
    scatter!(ax, run_numbers, min_ms, 
            color=:green, 
            markersize=10,
            marker=:circle,
            inspector_label = (self, i, p) -> "soon")
    
    lines!(ax, run_numbers, median_ms, color=:orange, linewidth=2, label="Median")
    scatter!(ax, run_numbers, median_ms, 
            color=:orange, 
            markersize=10,
            marker=:circle,
            inspector_label = (self, i, p) -> "soon")
    
    axislegend(ax, position=:lt, framevisible=true)
    
    DataInspector(fig)
    
    return fig
end

function create_benchmark_row(history, benchmark_name)
    subbench_names = get_subbenchmark_names(history, benchmark_name)
    
    plots = []
    for subbench_name in subbench_names
        timestamps, mean_times, min_times, median_times, memory, allocs = 
            extract_timeseries_with_timestamps(history, benchmark_name, subbench_name)
        
        title = subbench_name
        fig = create_benchmark_plot(timestamps, mean_times, min_times, median_times, 
                                    memory, allocs, title)
        push!(plots, fig)
    end
    
    return plots
end

function create_dashboard()
    history_file = "data/history.json"
    
    if !isfile(history_file)
        println("file not found")
        return nothing
    end
    
    history = load_history(history_file)
    benchmark_names = get_benchmark_names(history)
    
    if isempty(benchmark_names)
        println("history empty")
        return nothing
    end
    
    app = App() do session
        header = DOM.div(
            DOM.h1("Trixi.jl Benchmarkk Dashboard", 
                   style="text-align: center; color: #2c3e50; margin: 20px 0;"),
            DOM.hr(style="border: 1px solid #ecf0f1; margin: 20px 0;")
        )
        
        all_benchmarks = []
        
        for benchmark_name in benchmark_names
            bench_title = DOM.h2(benchmark_name, 
                                 style="color: #34495e; margin-top: 30px; margin-bottom: 15px;")
            push!(all_benchmarks, bench_title)
            
            plots = create_benchmark_row(history, benchmark_name)
            
            plots_row = DOM.div(
                [plot for plot in plots]...,
                style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin-bottom: 30px;"
            )
            
            push!(all_benchmarks, plots_row)
            push!(all_benchmarks, DOM.hr(style="border: 1px solid #ecf0f1; margin: 30px 0;"))
        end
        
        return DOM.div(
            header,
            DOM.div(all_benchmarks...),
            style="""
                font-family: Arial, sans-serif; 
                padding: 30px; 
                max-width: 1600px; 
                margin: auto;
                background-color: #f8f9fa;
            """
        )
    end
    
    return app
end

function start_dashboard(; port=8000)
    app = create_dashboard()
    
    if isnothing(app)
        return
    end
    
    server = Bonito.Server(app, "0.0.0.0", port)
    
    println("URL: http://localhost:$port")
    
    try
        wait(server)
    catch e
        if isa(e, InterruptException)
            println("\n\nstop")
        else
            rethrow(e)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    port = length(ARGS) > 0 ? parse(Int, ARGS[1]) : 8000
    start_dashboard(port=port)
end
