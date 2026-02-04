using Pkg

data_dir = length(ARGS) >= 1 ? ARGS[1] : "data"
group_name = length(ARGS) >= 2 ? ARGS[2] : get(ENV, "BENCHMARK_GROUP", "default")
benchmark_script = length(ARGS) >= 3 ? ARGS[3] : ""
commit_sha = get(ENV, "GITHUB_SHA", "")

action_path = joinpath(@__DIR__, "..")

using BenchmarkTools

if !isempty(benchmark_script) && isfile(benchmark_script)
    include(benchmark_script)
    suite = SUITE
elseif group_name == "trixi" && isfile(joinpath(action_path, "src/benchmarks_trixi.jl"))
    include(joinpath(action_path, "src/benchmarks_trixi.jl"))
    suite = SUITE
elseif group_name == "enzyme" && isfile(joinpath(action_path, "src/benchmarks_enzyme.jl"))
    include(joinpath(action_path, "src/benchmarks_enzyme.jl"))
    suite = SUITE_ENZYME
else
    error("No benchmark script found. Provide benchmark_script input or use built-in group (trixi, enzyme).")
end

Pkg.activate(action_path)
Pkg.instantiate()
include(joinpath(action_path, "src/HistoryManager.jl"))
using .HistoryManager

results = run(suite, verbose=true)

save_benchmark_results(results, group_name; data_dir=data_dir, commit_hash=commit_sha)
