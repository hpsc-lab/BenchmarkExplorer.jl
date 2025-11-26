module HistoryManager

export save_results_to_history, load_history, get_benchmark_names, 
       get_subbenchmark_names, extract_timeseries_with_timestamps

using BenchmarkTools
using JSON
using Dates

function save_results_to_history(results::BenchmarkGroup, history_file::String)
    history = if isfile(history_file)
        JSON.parsefile(history_file)
    else
        Dict{String, Any}()
    end
    
    run_numbers = [parse(Int, k) for k in keys(history) if all(isdigit, k)]
    next_run = isempty(run_numbers) ? 1 : maximum(run_numbers) + 1
    
    timestamp = Dates.format(now(), "yyyy-mm-ddTHH:MM:SS")
    julia_version = string(VERSION)
    
    flattened = Dict{String, Any}()
    
    function flatten_group(group, prefix="")
        for (key, value) in group
            path = isempty(prefix) ? key : "$prefix/$key"
            
            if value isa BenchmarkGroup
                flatten_group(value, path)
            else
                trial = value isa BenchmarkTools.Trial ? value : run(value)
                
                flattened[path] = Dict(
                    "mean_time_ns" => mean(trial).time,
                    "min_time_ns" => minimum(trial).time,
                    "median_time_ns" => median(trial).time,
                    "max_time_ns" => maximum(trial).time,
                    "std_time_ns" => std(trial).time,
                    "memory_bytes" => trial.memory,
                    "allocs" => trial.allocs,
                    "samples" => length(trial),
                    "timestamp" => timestamp,
                    "julia_version" => julia_version
                )
            end
        end
    end
    
    flatten_group(results)
    
    for (bench_path, data) in flattened
        if !haskey(history, bench_path)
            history[bench_path] = Dict{String, Any}()
        end
        history[bench_path][string(next_run)] = data
    end
    
    mkpath(dirname(history_file))
    
    open(history_file, "w") do io
        JSON.print(io, history, 2)
    end
    
    println("Saved run #$next_run to $history_file")
    return next_run
end

function load_history(history_file::String)
    if !isfile(history_file)
        return Dict{String, Any}()
    end
    return JSON.parsefile(history_file)
end

function get_benchmark_names(history::Dict{String, Any})
    bench_names = Set{String}()
    
    for bench_path in keys(history)
        parts = split(bench_path, "/")
        if length(parts) >= 2
            # For "tree_2d_dgsem/elixir_euler_ec.jl/p3_rhs!" -> "tree_2d_dgsem/elixir_euler_ec.jl"
            bench_name = join(parts[1:end-1], "/")
            push!(bench_names, bench_name)
        else
            push!(bench_names, bench_path)
        end
    end
    
    return sort(collect(bench_names))
end

function get_subbenchmark_names(history::Dict{String, Any}, benchmark_name::String)
    subbench_names = String[]
    
    for bench_path in keys(history)
        if startswith(bench_path, benchmark_name * "/")
            push!(subbench_names, bench_path)
        elseif bench_path == benchmark_name
            push!(subbench_names, bench_path)
        end
    end
    
    return sort(subbench_names)
end

function extract_timeseries_with_timestamps(history::Dict{String, Any}, 
                                           benchmark_name::String, 
                                           subbench_name::String)
    # subbench_name is the FULL path like "tree_2d_dgsem/elixir_euler_ec.jl/p3_rhs!"
    if !haskey(history, subbench_name)
        return (DateTime[], Float64[], Float64[], Float64[], Int[], Int[])
    end
    
    runs = history[subbench_name]
    run_numbers = sort(parse.(Int, keys(runs)))
    
    timestamps = DateTime[]
    mean_times = Float64[]
    min_times = Float64[]
    median_times = Float64[]
    memory = Int[]
    allocs = Int[]
    
    for run_num in run_numbers
        data = runs[string(run_num)]
        
        # Handle both old and new data formats
        if isa(data, Dict)
            push!(timestamps, DateTime(get(data, "timestamp", "2024-01-01T00:00:00")))
            push!(mean_times, Float64(data["mean_time_ns"]))
            push!(min_times, Float64(data["min_time_ns"]))
            push!(median_times, Float64(data["median_time_ns"]))
            push!(memory, Int(data["memory_bytes"]))
            push!(allocs, Int(data["allocs"]))
        else
            # Old format - single number
            @warn "Old data format detected for $subbench_name run $run_num, skipping"
            continue
        end
    end
    
    return (timestamps, mean_times, min_times, median_times, memory, allocs)
end

end # module
