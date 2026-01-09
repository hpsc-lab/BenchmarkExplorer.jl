module BenchmarkExplorer

include("HistoryManager.jl")
using .HistoryManager

export save_benchmark_results,
       load_history,
       load_by_hash,
       generate_all_runs_index,
       extract_timeseries_with_timestamps

end
