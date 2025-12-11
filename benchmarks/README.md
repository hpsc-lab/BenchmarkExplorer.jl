# Benchmark Suites

Example benchmark suites for BenchmarkExplorer.

## Structure

```
benchmarks/
├── trixi/      - Trixi.jl benchmarks
└── enzyme/     - Enzyme.jl benchmarks
```

Each suite has `Project.toml` and `benchmarks.jl`.

## Running

```bash
cd benchmarks/trixi
julia --project=. benchmarks.jl
```

## Creating New Suite

Create directory with `benchmarks.jl`:

```julia
using BenchmarkTools

push!(LOAD_PATH, joinpath(@__DIR__, "../.."))
using BenchmarkExplorerCore

const SUITE = BenchmarkGroup()
SUITE["test"] = @benchmarkable my_function()

if abspath(PROGRAM_FILE) == @__FILE__
    results = run(SUITE, verbose=true)
    save_benchmark_results(results, "../../data/history.json")
end
```

## CI Integration

See `.github/workflows/benchmarks.yml` for automated tracking.

History persists in `gh-pages` branch.
