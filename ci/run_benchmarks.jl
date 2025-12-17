using Pkg
Pkg.activate(".")
Pkg.instantiate()

using BenchmarkTools

include("../src/benchmarks_trixi.jl")
include("../src/HistoryManager.jl")
using .HistoryManager

data_dir = length(ARGS) >= 1 ? ARGS[1] : "data"
group_name = length(ARGS) >= 2 ? ARGS[2] : get(ENV, "BENCHMARK_GROUP", "trixi")
commit_sha = get(ENV, "GITHUB_SHA", "")

results = run(SUITE, verbose=true)

save_benchmark_results(results, group_name; data_dir=data_dir, commit_hash=commit_sha)
