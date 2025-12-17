using Pkg
Pkg.activate(".")
Pkg.instantiate()

data_dir = length(ARGS) >= 1 ? ARGS[1] : "data"
group_name = length(ARGS) >= 2 ? ARGS[2] : get(ENV, "BENCHMARK_GROUP", "trixi")
commit_sha = get(ENV, "GITHUB_SHA", "")

if group_name == "trixi"
    Pkg.add(["Trixi", "OrdinaryDiffEq"])
    using BenchmarkTools
    include("../src/benchmarks_trixi.jl")
    suite = SUITE
elseif group_name == "enzyme"
    Pkg.add("Enzyme")
    using BenchmarkTools
    include("../src/benchmarks_enzyme.jl")
    suite = SUITE_ENZYME
else
    error("Unknown group: $group_name")
end

include("../src/HistoryManager.jl")
using .HistoryManager

results = run(suite, verbose=true)

save_benchmark_results(results, group_name; data_dir=data_dir, commit_hash=commit_sha)
