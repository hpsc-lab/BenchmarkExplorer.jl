using Pkg
Pkg.activate(dirname(@__DIR__))

using BenchmarkTools

include(joinpath(dirname(@__DIR__), "src", "benchmarks_trixi.jl"))
include(joinpath(dirname(@__DIR__), "src", "benchmarks_enzyme.jl"))
include(joinpath(dirname(@__DIR__), "src", "HistoryManager.jl"))
using .HistoryManager

function run_and_save_trixi(; data_dir=joinpath(dirname(@__DIR__), "data"), commit_hash="")
    results = run(SUITE, verbose=true)
    save_benchmark_results(results, "trixi"; data_dir=data_dir, commit_hash=commit_hash)
    return results
end

function run_and_save_enzyme(; data_dir=joinpath(dirname(@__DIR__), "data"), commit_hash="")
    results = run(SUITE_ENZYME, verbose=true)
    save_benchmark_results(results, "enzyme"; data_dir=data_dir, commit_hash=commit_hash)
    return results
end

function run_all_benchmarks(; data_dir=joinpath(dirname(@__DIR__), "data"), commit_hash="")
    try
        run_and_save_trixi(data_dir=data_dir, commit_hash=commit_hash)
    catch e
        @error "Trixi benchmarks failed" exception=e
    end

    try
        run_and_save_enzyme(data_dir=data_dir, commit_hash=commit_hash)
    catch e
        @error "Enzyme benchmarks failed" exception=e
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_all_benchmarks()
end
