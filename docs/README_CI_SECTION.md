# Using BenchmarkExplorer in CI

GitHub Action for automated benchmark tracking with persistent history.

## Quick Start

Create benchmark suite (`src/benchmarks.jl`):

```julia
using BenchmarkTools

const SUITE = BenchmarkGroup()
SUITE["basic"] = @benchmarkable rand(100, 100) * rand(100, 100)
```

Add workflow (`.github/workflows/benchmarks.yml`):

```yaml
name: Benchmarks

on:
  schedule:
    - cron: '0 2 * * *'

permissions:
  contents: write

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hpsc-lab/BenchmarkExplorer.jl@main
        with:
          benchmark_script: 'src/benchmarks.jl'
```

Benchmarks run automatically, results persist in `gh-pages` branch.

## Persistence

History accumulation via `gh-pages` branch:

1. Fetch existing history from `gh-pages`
2. Run benchmarks, add new results with incremental run numbers
3. Push updated history back to `gh-pages`

Benefits:
- Full history preserved
- No main branch pollution
- Stateless workflow runs
- GitHub Pages hosting enabled

## Viewing Results

Local dashboard:
```bash
julia dashboard.jl
```

GitHub Pages (enable in repo settings):
```
https://username.github.io/repo/
```

Raw JSON:
```
https://username.github.io/repo/benchmarks/history.json
```

## Documentation

- Migration guide: [docs/VALENTIN_MIGRATION_GUIDE.md](docs/VALENTIN_MIGRATION_GUIDE.md)
- Pages setup: [docs/GITHUB_PAGES_SETUP.md](docs/GITHUB_PAGES_SETUP.md)
