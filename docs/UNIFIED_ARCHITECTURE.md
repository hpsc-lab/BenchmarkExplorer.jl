# Unified Dashboard Architecture

BenchmarkExplorer.jl now uses a unified architecture with a shared core and multiple rendering backends.

## Architecture Overview

```
┌─────────────────────────────────────┐
│      BenchmarkUI Core Module        │
│  - Data loading & processing        │
│  - Statistics calculation           │
│  - Plot data preparation            │
│  - Formatting utilities             │
└──────────────┬──────────────────────┘
               │
       ┌───────┴───────┐
       │               │
       ▼               ▼
┌─────────────┐  ┌─────────────────┐
│ Interactive │  │  Static Export  │
│   Bonito    │  │   Plotly.js     │
│ + WGLMakie  │  │                 │
└─────────────┘  └─────────────────┘
```

## Components

### 1. **BenchmarkUI Core** (`src/BenchmarkUI.jl`)

Shared module providing:
- `load_dashboard_data()` - Load benchmark data from disk
- `prepare_plot_data()` - Prepare data for visualization
- `calculate_stats()` - Compute statistics across benchmarks
- `format_time_short()`, `format_memory()` - Display formatting
- `get_benchmark_groups()` - Organize benchmarks by hierarchy

### 2. **Interactive Dashboard** (`dashboard_interactive.jl`)

**Technology:** Bonito.jl + WGLMakie.jl

**Features:**
- Full Julia server-side reactivity
- Real-time plot updates with Observables
- Advanced zoom and pan controls
- Live data filtering and search
- Dark mode toggle
- Multiple metric views (mean/min/median)

**Use Cases:**
- Local development and testing
- Pluto.jl notebook integration
- VSCode/Jupyter integration
- Real-time benchmark monitoring

**Usage:**
```bash
julia dashboard_interactive.jl [port] [data_dir]
```

### 3. **Static Export** (`ci/generate_static_page_plotly.jl`)

**Technology:** Plotly.js (pure JavaScript)

**Features:**
- Fully interactive without Julia server
- Complete zoom, pan, box select functionality
- Export plots to PNG from browser
- Responsive design
- Dark mode support
- CSV data export
- Progressive history loading

**Use Cases:**
- GitHub Pages deployment
- Static site hosting
- Sharing benchmark results
- CI/CD integration

**Usage:**
```bash
julia ci/generate_static_page_plotly.jl data/ output.html group_name repo_url commit_sha
```

## Comparison Matrix

| Feature | Interactive (Bonito) | Static (Plotly.js) |
|---------|---------------------|-------------------|
| **Requires Julia Server** | ✅ Yes | ❌ No |
| **Zoom & Pan** | ✅ Full | ✅ Full |
| **Box Select** | ⚠️ Limited | ✅ Yes |
| **Export to PNG** | ⚠️ Complex | ✅ One-click |
| **Real-time Updates** | ✅ Yes | ❌ No |
| **File Size** | N/A | ~3MB (CDN) |
| **Load Time** | Instant | ~1s (CDN) |
| **Dark Mode** | ✅ Yes | ✅ Yes |
| **Search/Filter** | ✅ Yes | ✅ Yes |
| **CSV Export** | ✅ Yes | ✅ Yes |
| **Mobile Support** | ⚠️ Limited | ✅ Full |

## Data Flow

Both modes use the same data structure:

```
data/
├── by_date/              # Benchmarks by date
├── by_group/             # Incremental runs per group
├── by_hash/              # Lookups by git commit
├── index.json            # Metadata index
├── latest_100.json       # Fast-load cache (used by both)
└── all_runs_index.json   # Full history index
```

### Interactive Mode:
```julia
data = BenchmarkUI.load_dashboard_data("data")
# Creates Bonito App with WGLMakie plots
# Serves on http://localhost:8000
```

### Static Mode:
```julia
data = BenchmarkUI.load_dashboard_data("data")
# Generates Plotly.js traces
# Writes standalone HTML file
```

## Integration Examples

### GitHub Actions

```yaml
- name: Generate static dashboard
  run: |
    julia ci/generate_static_page_plotly.jl \
      data/ index.html myproject \
      "${{ github.server_url }}/${{ github.repository }}" \
      "${{ github.sha }}"
```

### Pluto.jl Notebook

```julia
using Pluto
using BenchmarkExplorer

# In Pluto notebook:
include("dashboard_interactive.jl")
create_interactive_dashboard("data"; port=8000)
```

### Local Development

```bash
# Interactive mode (recommended for development)
julia dashboard_interactive.jl

# Generate static page for testing
julia ci/generate_static_page_plotly.jl data/ test.html mygroup https://github.com/user/repo abc123
```

## Migration Guide

### From Old Chart.js Dashboard

The old `ci/generate_static_page.jl` (Chart.js) is still available but deprecated. To migrate:

1. **Switch to Plotly.js:**
   ```bash
   # Old
   julia ci/generate_static_page.jl ...

   # New
   julia ci/generate_static_page_plotly.jl ...
   ```

2. **Update action.yml:**
   ```yaml
   # Replace generate_static_page.jl with generate_static_page_plotly.jl
   ```

3. **Benefits:**
   - Better zoom/pan controls
   - Professional scientific plotting
   - Export to PNG
   - Larger ecosystem support

### Adding Custom Metrics

To add new metrics, extend `BenchmarkUI`:

```julia
# src/BenchmarkUI.jl
function prepare_custom_metric(history, benchmark_path)
    # Your custom calculation
    return (x=..., y=...)
end
```

Both interactive and static modes will automatically use it.

## Performance Considerations

### Interactive Mode
- Memory: ~100-200MB for typical datasets
- Startup: ~2-5 seconds (Julia compilation)
- Update latency: <100ms (reactive)

### Static Mode
- File size: 3-5MB (with CDN), 8-10MB (embedded)
- Load time: 1-2 seconds (browser rendering)
- Interactivity: Client-side only (no server)

## Future Enhancements

Planned features:
- [ ] WebSocket live updates for interactive mode
- [ ] Comparison mode (multiple commits side-by-side)
- [ ] Statistical tests (t-test, Mann-Whitney)
- [ ] Regression detection alerts
- [ ] Custom plot themes
- [ ] 3D visualization for multi-dimensional benchmarks

## Troubleshooting

### Interactive Mode Issues

**Problem:** "Port already in use"
```bash
# Solution: Use different port
julia dashboard_interactive.jl 8001
```

**Problem:** Plots not updating
```bash
# Solution: Check Observable connections
# Restart Julia session
```

### Static Mode Issues

**Problem:** Large HTML files
```bash
# Solution: Use CDN mode (default)
# File size: ~3MB vs 10MB embedded
```

**Problem:** Plots not interactive
```bash
# Solution: Ensure Plotly.js CDN is accessible
# Check browser console for errors
```

## Contributing

When contributing to the dashboard:
1. Add core logic to `BenchmarkUI.jl`
2. Update both interactive and static renderers
3. Test both modes
4. Update this documentation

## License

MIT License - see LICENSE file for details.
