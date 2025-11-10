module HistoryManager

using JSON
using Dates
using Statistics

export save_benchmark_results, load_history, get_benchmark_names, 
       get_subbenchmark_names, extract_timeseries_with_timestamps


function save_benchmark_results(suite_results, history_file="data/history.json")
    if isfile(history_file)
        history = JSON.parsefile(history_file)
    else
        history = Dict()
    end
    
    run_timestamp = string(now())
    
    for (benchname, bench_group) in suite_results
        if !haskey(history, benchname)
            history[benchname] = Dict()
        end
        
        existing_runs = keys(history[benchname])
        next_run_number = isempty(existing_runs) ? 1 : maximum(parse(Int, k) for k in existing_runs) + 1
        
        run_data = Dict()
        for (subbench_name, trial) in bench_group
            run_data[subbench_name] = Dict(
                "mean_time_ns" => mean(trial).time,
                "min_time_ns" => minimum(trial).time,
                "median_time_ns" => median(trial).time,
                "memory_bytes" => trial.memory,
                "allocs" => trial.allocs,
                "timestamp" => run_timestamp
            )
        end
        
        history[benchname][string(next_run_number)] = run_data
    end
    
    mkpath(dirname(history_file))
    open(history_file, "w") do f
        JSON.print(f, history, 2)
    end    
    return history
end

function load_history(history_file="data/history.json")
    if !isfile(history_file)
        error(" $history_file not")
    end
    return JSON.parsefile(history_file)
end

function get_benchmark_names(history)
    return sort(collect(keys(history)))
end


function get_subbenchmark_names(history, benchmark_name)
    first_run = history[benchmark_name][first(keys(history[benchmark_name]))]
    return sort(collect(keys(first_run)))
end


function extract_timeseries_with_timestamps(history, benchmark_name, subbench_name)
    run_numbers = sort(parse.(Int, keys(history[benchmark_name])))
    
    timestamps = DateTime[]
    mean_times = Float64[]
    min_times = Float64[]
    median_times = Float64[]
    memory = Float64[]
    allocs = Int[]
    
    for run_num in run_numbers
        data = history[benchmark_name][string(run_num)][subbench_name]
        push!(timestamps, DateTime(data["timestamp"]))
        push!(mean_times, data["mean_time_ns"])
        push!(min_times, data["min_time_ns"])
        push!(median_times, data["median_time_ns"])
        push!(memory, data["memory_bytes"])
        push!(allocs, data["allocs"])
    end
    
    return timestamps, mean_times, min_times, median_times, memory, allocs
end

end
