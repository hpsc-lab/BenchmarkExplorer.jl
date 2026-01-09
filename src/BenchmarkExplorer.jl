module BenchmarkExplorer

include("HistoryManager.jl")
using .HistoryManager

include("BenchmarkUI.jl")
using .BenchmarkUI

export save_benchmark_results,
       load_history,
       load_by_hash,
       generate_all_runs_index,
       extract_timeseries_with_timestamps,
       flatten_benchmarks,
       get_benchmark_names,
       get_subbenchmark_names,
       DashboardData,
       load_dashboard_data,
       prepare_plot_data,
       calculate_stats,
       format_time_short,
       format_memory,
       get_benchmark_groups,
       format_time_ago,
       get_benchmark_summary,
       format_commit_hash

end
