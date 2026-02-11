using Pkg

data_dir = length(ARGS) >= 1 ? ARGS[1] : "data"
group_name = length(ARGS) >= 2 ? ARGS[2] : get(ENV, "BENCHMARK_GROUP", "default")
benchmark_script = length(ARGS) >= 3 ? ARGS[3] : ""
commit_sha = get(ENV, "GITHUB_SHA", "")

action_path = joinpath(@__DIR__, "..")

if group_name == "nanosoldier"
    Pkg.activate(action_path)
    Pkg.instantiate()
    include(joinpath(action_path, "scripts/import_nanosoldier.jl"))
    nanosoldier_tmp = joinpath(data_dir, "nanosoldier_raw")
    import_recent_comparisons(nanosoldier_tmp; limit=30)
    convert_to_explorer_format(nanosoldier_tmp, data_dir, "nanosoldier")
else
    benchmark_script_abs = !isempty(benchmark_script) ? abspath(benchmark_script) : ""
    is_external = !isempty(benchmark_script_abs) && isfile(benchmark_script_abs)

    if !is_external
        benchmark_project = joinpath(action_path, "benchmarks", group_name)
        if isdir(benchmark_project)
            Pkg.activate(benchmark_project)
            Pkg.instantiate()
        else
            error("Unknown group: $group_name. Provide benchmark_script for external use.")
        end
    end

    using BenchmarkTools

    if is_external
        include(benchmark_script_abs)
        suite = SUITE
    elseif group_name == "trixi"
        include(joinpath(action_path, "src/benchmarks_trixi.jl"))
        suite = SUITE
    elseif group_name == "enzyme"
        include(joinpath(action_path, "src/benchmarks_enzyme.jl"))
        suite = SUITE_ENZYME
    else
        error("No benchmark script found.")
    end

    Pkg.activate(action_path)
    Pkg.instantiate()
    include(joinpath(action_path, "src/HistoryManager.jl"))
    using .HistoryManager

    results = run(suite, verbose=true)

    save_benchmark_results(results, group_name; data_dir=data_dir, commit_hash=commit_sha)
end
