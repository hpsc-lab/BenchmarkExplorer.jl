using Pkg
Pkg.activate(dirname(@__DIR__))

using BenchmarkTools

include(joinpath(dirname(@__DIR__), "src", "benchmarks_trixi.jl"))
include(joinpath(dirname(@__DIR__), "src", "HistoryManager.jl"))
using .HistoryManager

function run_and_save_trixi(; data_dir=joinpath(dirname(@__DIR__), "data"), commit_hash="")
    results = run(SUITE, verbose=true)
    save_benchmark_results(results, "trixi"; data_dir=data_dir, commit_hash=commit_hash)
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_and_save_trixi()
end