# BenchmarkExplorer.jl

Performance benchmarking and visualization toolkit for Julia projects with persistent history tracking and static HTML dashboards.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Julia](https://img.shields.io/badge/Julia-1.10+-purple.svg)](https://julialang.org)

The CI action automatically generates a regression badge you can embed in your README:

```markdown
![regressions](https://your-org.github.io/your-repo/benchmarks/nanosoldier-badge.svg)
```

## Features

- **Static HTML Dashboard**: Interactive benchmark pages deployed to GitHub Pages via Plotly.js
- **Heatmap View**: Visual regression detection across commits with color-coded cells
- **Persistent History**: Incremental storage across CI runs, organized by group
- **GitHub Actions Integration**: Drop-in composite action for any Julia project
- **NanosoldierReports Integration**: Automatically imports Julia CI benchmark data from [NanosoldierReports](https://github.com/JuliaCI/NanosoldierReports)
- **Dark Mode**: Persists across pages via localStorage
- **CSV Export**: Export benchmark data for external analysis
- **URL State**: Shareable links preserve view, filter, and selected benchmark

## Quick Start

### Using as a GitHub Action

Add to `.github/workflows/benchmarks.yml`:

```yaml
name: Benchmarks

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 2 * * *'

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hpsc-lab/BenchmarkExplorer.jl@main
        with:
          benchmark_script: 'benchmarks/benchmarks.jl'
          group_name: 'myproject'
          julia_version: '1.11'
          persist_to_branch: 'gh-pages'
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

Your benchmark script must define a `SUITE` variable of type `BenchmarkGroup`:

```julia
using BenchmarkTools

const SUITE = BenchmarkGroup()
SUITE["sin"] = @benchmarkable sin(1.0)
SUITE["cos"] = @benchmarkable cos(1.0)
```

### GitHub Pages Setup

1. Enable GitHub Pages in repository settings
2. Source: `gh-pages` branch, `benchmarks/` directory
3. Results appear at `https://username.github.io/repository/`

### Action Inputs

| Input | Default | Description |
|---|---|---|
| `benchmark_script` | — | Path to Julia file defining `SUITE` |
| `benchmark_project` | `@.` | `--project` flag for the benchmark script |
| `group_name` | `trixi` | Benchmark group name (`trixi`, `enzyme`, `nanosoldier`, or custom) |
| `julia_version` | `1.11` | Julia version |
| `persist_to_branch` | `gh-pages` | Branch for storing history and HTML |
| `persist_path` | `benchmarks/` | Path within the persist branch |
| `commit_base_url` | repo URL | Base URL for commit links |
| `github_token` | — | GitHub token (required) |

## NanosoldierReports Integration

Set `group_name: nanosoldier` to automatically fetch and visualize Julia's official CI benchmark data:

```yaml
- uses: hpsc-lab/BenchmarkExplorer.jl@main
  with:
    group_name: nanosoldier
    github_token: ${{ secrets.GITHUB_TOKEN }}
```

This fetches comparison reports from [JuliaCI/NanosoldierReports](https://github.com/JuliaCI/NanosoldierReports), parses HEAD and BASE measurements from `data.tar.zst`, computes real time ratios, and organizes benchmarks by category (inference, array, broadcast, etc.).

## Local Usage

```julia
using BenchmarkExplorer
using BenchmarkTools

suite = BenchmarkGroup()
suite["example"] = @benchmarkable sin(1.0)

results = run(suite)
save_benchmark_results(results, "myproject"; data_dir="data", commit_hash="abc123")
```

Start the interactive local dashboard:

```bash
julia dashboard_interactive.jl
# or
julia dashboard.jl
```

Open http://localhost:8000 in your browser.

## Data Structure

```
data/
├── by_group/
│   ├── myproject/
│   │   └── history.json     # Per-benchmark time series
│   └── myproject_subcategory/
│       └── history.json
├── by_date/
│   └── 2026-03/
│       └── 18/
│           └── myproject.json
├── by_hash/
│   └── abc1234.../
│       └── myproject.json
├── index.json               # Groups metadata
└── latest_100.json          # Recent runs cache
```

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [BenchmarkTools.jl](https://github.com/JuliaCI/BenchmarkTools.jl)
- [Plotly.js](https://plotly.com/javascript/)
- [NanosoldierReports](https://github.com/JuliaCI/NanosoldierReports)
