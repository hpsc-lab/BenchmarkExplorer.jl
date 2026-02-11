# Setting up BenchmarkExplorer in External Repository

Guide for integrating BenchmarkExplorer.jl into your project (e.g., trixi-performance-tracker).

## Prerequisites

- GitHub repository with benchmarks using BenchmarkTools.jl
- Benchmark file that defines `SUITE` variable
- GitHub Pages enabled (optional, for static dashboard)

## Quick Setup

### Step 1: Create benchmark file

Create `benchmarks.jl` with your benchmarks:

```julia
using BenchmarkTools

SUITE = BenchmarkGroup()

SUITE["math"] = BenchmarkGroup()
SUITE["math"]["sin"] = @benchmarkable sin(0.5)
SUITE["math"]["cos"] = @benchmarkable cos(0.5)

SUITE["array"] = BenchmarkGroup()
SUITE["array"]["sum"] = @benchmarkable sum(rand(1000))
```

### Step 2: Add workflow file

Create `.github/workflows/benchmarks.yml`:

```yaml
name: Benchmarks

on:
  schedule:
    - cron: '0 3 * * *'
  push:
    branches: [main]
    paths:
      - 'benchmarks.jl'
      - '.github/workflows/benchmarks.yml'
  workflow_dispatch:

permissions:
  contents: write

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hpsc-lab/BenchmarkExplorer.jl@main
        with:
          benchmark_script: 'benchmarks.jl'
          group_name: 'myproject'
          julia_version: '1.11'
          persist_to_branch: 'gh-pages'
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

### Step 2: Enable GitHub Pages

1. Go to repository Settings → Pages
2. Source: Deploy from branch `gh-pages`
3. Folder: `/ (root)`

### Step 3: Run workflow

Push changes or manually trigger workflow. Results will be at:
`https://<username>.github.io/<repository>/`

## Migration from benchmark-action

If you're currently using `benchmark-action`, here's how to migrate:

### Before (benchmark-action):

```yaml
- name: Run benchmarks
  run: julia --project runbenchmarks.jl

- name: Store results
  uses: benchmark-action/github-action-benchmark@v1
  with:
    tool: 'julia'
    output-file-path: output.json
    github-token: ${{ secrets.GITHUB_TOKEN }}
    auto-push: true
```

### After (BenchmarkExplorer):

```yaml
- name: Run benchmarks
  run: |
    julia --project=. -e '
      using BenchmarkTools, JSON, Dates
      include("benchmarks.jl")
      results = run(SUITE, verbose=true)
      # ... (flatten and save as shown above)
    '

- uses: hpsc-lab/BenchmarkExplorer.jl@main
  with:
    results_file: 'benchmark_results.json'
    group_name: 'myproject'
    persist_to_branch: 'gh-pages'
    generate_static_page: 'true'
    github_token: ${{ secrets.GITHUB_TOKEN }}
```

## Example: trixi-performance-tracker

For https://github.com/vchuravy/trixi-performance-tracker:

Replace current `Nightly.yml` with:

```yaml
name: Trixi Benchmarks

on:
  schedule:
    - cron: '0 16 * * *'
  workflow_dispatch:

permissions:
  contents: write

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Trixi dependency
        run: |
          julia --project=. -e '
            using Pkg
            Pkg.add(url="https://github.com/trixi-framework/Trixi.jl", rev="main")
            Pkg.instantiate()
          '

      - uses: hpsc-lab/BenchmarkExplorer.jl@main
        with:
          benchmark_script: 'benchmarks.jl'
          group_name: 'trixi'
          julia_version: '1.10'
          persist_to_branch: 'gh-pages'
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

The action will:
1. Set up Julia 1.10
2. Run benchmarks from `benchmarks.jl`
3. Save results with history
4. Generate static HTML dashboard
5. Push to `gh-pages` branch

View results at: `https://vchuravy.github.io/trixi-performance-tracker/`

## Features Comparison

| Feature | benchmark-action | BenchmarkExplorer |
|---------|-----------------|-------------------|
| Interactive dashboard | No | Yes |
| Static HTML page | Basic chart | Full dashboard |
| Multiple groups | No | Yes |
| History by commit | Yes | Yes |
| History by date | No | Yes |
| Trend badges | No | Yes |
| CSV export | No | Yes |
| Dark mode | No | Yes |
| Regression alerts | Yes | Planned |
| Local development | No | Yes |

## Local Development

Test locally before pushing:

```bash
git clone https://github.com/hpsc-lab/BenchmarkExplorer.jl
cd BenchmarkExplorer.jl

julia --project=. -e 'using Pkg; Pkg.instantiate()'

julia dashboard.jl
```

Open http://localhost:8000

## Troubleshooting

### GitHub Pages not updating

Check that:
1. `gh-pages` branch exists
2. GitHub Pages is enabled in Settings
3. Workflow has `contents: write` permission

### Benchmarks not appearing

Verify JSON format:
```json
{
  "metadata": {
    "timestamp": "2026-01-28T10:00:00",
    "commit_hash": "abc123",
    "julia_version": "1.11.0"
  },
  "benchmarks": {
    "group/benchmark_name": {
      "mean_time_ns": 1000000,
      "min_time_ns": 900000,
      "median_time_ns": 950000
    }
  }
}
```

## Support

- Issues: https://github.com/hpsc-lab/BenchmarkExplorer.jl/issues
- Discussions: https://github.com/hpsc-lab/BenchmarkExplorer.jl/discussions
