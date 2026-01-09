# Quick Start Guide

## Two Modes of Operation

BenchmarkExplorer.jl now supports two modes:

1. **Interactive Dashboard** - For local development and Pluto.jl integration
2. **Static Export** - For GitHub Pages and static hosting

## Interactive Dashboard (Bonito + WGLMakie)

### Prerequisites
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Run Dashboard
```bash
# Default port 8000
julia dashboard_interactive.jl

# Custom port
julia dashboard_interactive.jl 9000

# Custom data directory
julia dashboard_interactive.jl 8000 path/to/data
```

### Open in Browser
```
http://localhost:8000
```

### Features
- ✅ Full zoom and pan controls
- ✅ Real-time metric switching (mean/min/median)
- ✅ Dark mode toggle
- ✅ Group visibility controls
- ✅ CSV export
- ✅ Percentage change mode

## Static Export (Plotly.js)

### Generate Static Page
```bash
julia ci/generate_static_page_plotly.jl \
  data/ \
  output.html \
  your_group_name \
  https://github.com/user/repo \
  commit_sha
```

### Example
```bash
julia ci/generate_static_page_plotly.jl \
  data/ \
  benchmarks.html \
  trixi \
  https://github.com/trixi-framework/Trixi.jl \
  abc123def
```

### Features
- ✅ Fully interactive without server
- ✅ Complete zoom, pan, box select
- ✅ Export plots to PNG
- ✅ Dark mode
- ✅ CSV export
- ✅ Mobile responsive
- ✅ 3MB total size (with CDN)

## GitHub Actions Integration

### Basic Workflow

```yaml
name: Benchmarks

on:
  push:
    branches: [main]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hpsc-lab/BenchmarkExplorer.jl@main
        with:
          benchmark_script: 'benchmarks/benchmarks.jl'
          group_name: 'myproject'
          persist_to_branch: 'gh-pages'
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

### Use Plotly.js (Recommended)

Update the action to use the new Plotly.js generator:

```yaml
- name: Generate static dashboard
  run: |
    julia --project=${{ github.action_path }} \
      ci/generate_static_page_plotly.jl \
      data/ index.html myproject \
      "${{ github.server_url }}/${{ github.repository }}" \
      "${{ github.sha }}"
```

## Pluto.jl Integration

```julia
### A Pluto.jl notebook ###
# v0.19.x

using Pkg
Pkg.activate(mktempdir())
Pkg.add(url="https://github.com/hpsc-lab/BenchmarkExplorer.jl")

begin
    using BenchmarkExplorer
    include("dashboard_interactive.jl")

    # Create dashboard
    create_interactive_dashboard("data"; port=8001)
end
```

Then open http://localhost:8001 in your browser.

## Data Format

Both modes use the same data structure:

```
data/
├── by_date/              # Organized by date
├── by_group/             # Incremental runs
├── by_hash/              # Git commit lookup
├── index.json            # Metadata
├── latest_100.json       # Quick-load cache
└── all_runs_index.json   # Full history
```

## Comparison

| Feature | Interactive | Static |
|---------|------------|--------|
| Server Required | Yes | No |
| Zoom/Pan | ✅ | ✅ |
| Export PNG | Limited | ✅ |
| Real-time Updates | ✅ | ❌ |
| File Size | N/A | ~3MB |
| Mobile | Limited | ✅ |

## Choosing the Right Mode

### Use Interactive Mode When:
- Local development and testing
- Pluto.jl notebook integration
- Need real-time data updates
- Working in VSCode/Jupyter

### Use Static Mode When:
- Deploying to GitHub Pages
- Sharing results publicly
- No Julia server available
- Need mobile access
- CI/CD pipelines

## Troubleshooting

### Interactive Mode

**Port already in use:**
```bash
julia dashboard_interactive.jl 8001
```

**Slow startup:**
First run compiles packages (~2-3 minutes). Subsequent runs are faster.

### Static Mode

**Large HTML file:**
File includes data inline. Use CDN mode (default) for smaller size.

**Plots not interactive:**
Check browser console. Ensure Plotly.js CDN is accessible.

## Next Steps

- Read [UNIFIED_ARCHITECTURE.md](UNIFIED_ARCHITECTURE.md) for architecture details
- Check [DATA_STRUCTURE.md](DATA_STRUCTURE.md) for data format
- See [BENCHMARK_CI.md](BENCHMARK_CI.md) for CI setup

## Support

- Issues: https://github.com/hpsc-lab/BenchmarkExplorer.jl/issues
- Discussions: https://github.com/hpsc-lab/BenchmarkExplorer.jl/discussions
