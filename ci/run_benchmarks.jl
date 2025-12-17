using Pkg

data_dir = length(ARGS) >= 1 ? ARGS[1] : "data"
group_name = length(ARGS) >= 2 ? ARGS[2] : get(ENV, "BENCHMARK_GROUP", "trixi")
commit_sha = get(ENV, "GITHUB_SHA", "")

benchmark_project = joinpath(@__DIR__, "..", "benchmarks", group_name)

if !isdir(benchmark_project)
    error("Unknown group: $group_name")
end

Pkg.activate(benchmark_project)
Pkg.instantiate()

using BenchmarkTools

if group_name == "trixi"
    include("../src/benchmarks_trixi.jl")
    suite = SUITE
elseif group_name == "enzyme"
    include("../src/benchmarks_enzyme.jl")
    suite = SUITE_ENZYME
else
    error("Unknown group: $group_name")
end

Pkg.activate(joinpath(@__DIR__, ".."))
include("../src/HistoryManager.jl")
using .HistoryManager

results = run(suite, verbose=true)

save_benchmark_results(results, group_name; data_dir=data_dir, commit_hash=commit_sha)
