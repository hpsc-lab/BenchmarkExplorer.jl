using Pkg
Pkg.activate(dirname(@__DIR__))

using BenchmarkTools

include(joinpath(dirname(@__DIR__), "src", "benchmarks_enzyme.jl"))
include(joinpath(dirname(@__DIR__), "src", "HistoryManager.jl"))
using .HistoryManager

function run_and_save_enzyme(; history_file=joinpath(dirname(@__DIR__), "data", "history_enzyme.json"))    
    results = run(SUITE_ENZYME, verbose=true)
    save_benchmark_results(results, history_file)
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_and_save_enzyme()
end
