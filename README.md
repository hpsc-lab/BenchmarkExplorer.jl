# BenchmarkExplorer.jl

Performance benchmarking and visualization toolkit for Julia projects with persistent history tracking and interactive dashboards.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Julia](https://img.shields.io/badge/Julia-1.10+-purple.svg)](https://julialang.org)

## Features

- **Interactive Dashboards**: Real-time visualization with WGLMakie.jl and Bonito.jl
- **Persistent History**: Track performance across commits with incremental storage
- **GitHub Integration**: Automated CI workflows with GitHub Actions
- **Multiple Storage Formats**: Organized by date, group, and commit hash
- **Static HTML Pages**: Shareable benchmark reports via GitHub Pages
- **Progressive Loading**: Fast startup with on-demand historical data access
- **CSV Export**: Export benchmark data for external analysis

## Quick Start

### Installation

```julia
using Pkg
Pkg.add(url="https://github.com/hpsc-lab/BenchmarkExplorer.jl")
```

### Running Benchmarks

```julia
using BenchmarkExplorer
using BenchmarkTools

suite = BenchmarkGroup()
suite["example"] = @benchmarkable sin(1.0)

results = run(suite)
save_benchmark_results(results, "myproject"; data_dir="data", commit_hash="abc123")
```

### Starting Dashboard

**Interactive Mode** (Bonito + WGLMakie - full features):
```bash
julia dashboard_interactive.jl
```

**Classic Mode** (original dashboard):
```bash
julia dashboard.jl
```

Open http://localhost:8000 in your browser.

> **New:** Interactive mode uses unified architecture with shared core for both local and static deployments.

## CI Integration

### GitHub Actions

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
          julia_version: '1.10'
          persist_to_branch: 'gh-pages'
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

### GitHub Pages

1. Enable GitHub Pages in repository settings
2. Source: `gh-pages` branch, root directory
3. View results at: `https://username.github.io/repository/`

## Documentation

- **[Quick Start Guide](docs/QUICK_START.md)** - Get started in 5 minutes
- **[External Setup](docs/EXTERNAL_SETUP.md)** - Use in your own repository
- [Unified Architecture](docs/UNIFIED_ARCHITECTURE.md) - Dual-mode system
- [Data Structure](docs/DATA_STRUCTURE.md) - Storage format specification

## Data Organization

```
data/
├── by_date/           # Benchmarks organized by date
├── by_group/          # Per-group incremental runs
├── by_hash/           # Lookup by git commit hash
├── index.json         # Metadata index
├── latest_100.json    # Recent runs cache
└── all_runs_index.json # Complete history index
```

## Example Projects

- [Trixi.jl Performance Tracker](https://github.com/vchuravy/trixi-performance-tracker)
- [Enzyme.jl Benchmarks](benchmarks/enzyme)

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for detailed architecture documentation.

### Local Testing

```bash
julia scripts/populate_history.jl
julia dashboard.jl
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Citation

If you use BenchmarkExplorer.jl in your research, please cite:

```bibtex
@software{benchmarkexplorer,
  title = {BenchmarkExplorer.jl: Performance Tracking for Julia},
  year = {2025},
  url = {https://github.com/hpsc-lab/BenchmarkExplorer.jl}
}
```

## Acknowledgments

Built with:
- [BenchmarkTools.jl](https://github.com/JuliaCI/BenchmarkTools.jl) - Benchmarking framework
- [Bonito.jl](https://github.com/SimonDanisch/Bonito.jl) - Web framework
- [WGLMakie.jl](https://github.com/MakieOrg/Makie.jl) - Plotting library
- [Trixi.jl](https://github.com/trixi-framework/Trixi.jl) - Example PDE solver
- [Enzyme.jl](https://github.com/EnzymeAD/Enzyme.jl) - Automatic differentiation

## Support

- **Issues**: [GitHub Issues](https://github.com/hpsc-lab/BenchmarkExplorer.jl/issues)
- **Discussions**: [GitHub Discussions](https://github.com/hpsc-lab/BenchmarkExplorer.jl/discussions)
