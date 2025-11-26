using Pkg
Pkg.activate(dirname(@__DIR__))

using BenchmarkTools

include(joinpath(dirname(@__DIR__), "src", "benchmarks_trixi.jl"))
include(joinpath(dirname(@__DIR__), "src", "benchmarks_enzyme.jl"))
include(joinpath(dirname(@__DIR__), "src", "HistoryManager.jl"))
using .HistoryManager

function run_and_save_trixi(; history_file=joinpath(dirname(@__DIR__), "data", "history_trixi.json"))
    results = run(SUITE, verbose=true)
    save_benchmark_results(results, history_file)
    return results
end

function run_and_save_enzyme(; history_file=joinpath(dirname(@__DIR__), "data", "history_enzyme.json"))
    results = run(SUITE_ENZYME, verbose=true)
    save_benchmark_results(results, history_file)
    return results
end

function run_all_benchmarks()
    try
        run_and_save_trixi()
    catch e
        println("Trixi benchmarks failed: $e")
    end

    try
        run_and_save_enzyme()
    catch e
        println("Enzyme benchmarks failed: $e")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_all_benchmarks()
end
