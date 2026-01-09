# Data Structure

## Overview

BenchmarkExplorer uses a hybrid storage system inspired by NanosoldierReports:
- Fast dashboard loading via `latest_100.json` cache
- Historical analysis via `by_date/` organization
- Efficient CI storage in gh-pages branch

## Directory Structure

```
data/
├── by_date/
│   └── YYYY-MM/                 # Year-month folders
│       └── DD/                  # Day folders
│           ├── trixi.json       # All trixi benchmarks for this run
│           ├── enzyme.json      # All enzyme benchmarks for this run
│           └── report.md        # Human-readable markdown report
├── by_group/
│   ├── trixi/                   # Per-group organization
│   │   ├── run_1.json
│   │   ├── run_2.json
│   │   └── run_N.json
│   └── enzyme/
│       ├── run_1.json
│       ├── run_2.json
│       └── run_N.json
├── by_hash/
│   ├── abc123.../               # Git commit hash
│   │   ├── trixi.json
│   │   └── enzyme.json
│   └── def456.../
│       ├── trixi.json
│       └── enzyme.json
├── index.json                   # Metadata index of all runs
├── latest_100.json              # Cache of last 100 runs for dashboard
└── all_runs_index.json          # Lightweight index for accessing all runs
```

## File Formats

### 1. Individual Run File (`by_group/{group}/run_N.json`)

Each run file contains all benchmarks for that specific run:

```json
{
  "metadata": {
    "run_number": 1,
    "group": "trixi",
    "timestamp": "2025-12-17T15:30:00.000",
    "julia_version": "1.11.5",
    "commit_hash": "abc123...",
    "machine": {
      "cpu": "Intel Core i7",
      "cores": 8,
      "memory_gb": 16
    }
  },
  "benchmarks": {
    "tree_2d_dgsem/elixir_euler_ec.jl/p7_rhs!": {
      "mean_time_ns": 7534969.149,
      "median_time_ns": 7491503.5,
      "min_time_ns": 6873196.0,
      "max_time_ns": 9043242.0,
      "std_time_ns": 148840.736,
      "memory_bytes": 0,
      "allocs": 0,
      "samples": 664
    }
  }
}
```

### 2. Date-organized File (`by_date/YYYY-MM/DD/{group}.json`)

Same format as individual run file, but organized by date for easy lookup.

### 3. Index File (`index.json`)

Metadata index of all runs for quick navigation:

```json
{
  "version": "2.0",
  "groups": {
    "trixi": {
      "runs": [
        {
          "run_number": 1,
          "timestamp": "2025-11-21T04:15:57.257",
          "date": "2025-11-21",
          "julia_version": "1.10.10",
          "commit_hash": "abc123",
          "benchmark_count": 42,
          "file_path": "by_group/trixi/run_1.json"
        },
        {
          "run_number": 2,
          "timestamp": "2025-11-26T10:56:49.765",
          "date": "2025-11-26",
          "julia_version": "1.11.5",
          "commit_hash": "def456",
          "benchmark_count": 42,
          "file_path": "by_group/trixi/run_2.json"
        }
      ],
      "total_runs": 2,
      "latest_run": 2,
      "first_run_date": "2025-11-21",
      "last_run_date": "2025-11-26"
    },
    "enzyme": {
      "runs": [...],
      "total_runs": 5,
      "latest_run": 5,
      "first_run_date": "2025-11-20",
      "last_run_date": "2025-11-26"
    }
  },
  "last_updated": "2025-12-17T15:30:00.000"
}
```

### 4. Latest Runs Cache (`latest_100.json`)

Pre-aggregated data for dashboard - last 100 runs in old format for fast loading:

```json
{
  "version": "2.0",
  "cached_at": "2025-12-17T15:30:00.000",
  "groups": {
    "trixi": {
      "tree_2d_dgsem/elixir_euler_ec.jl/p7_rhs!": {
        "1": {
          "mean_time_ns": 7464327.22,
          "median_time_ns": 7443232.0,
          "min_time_ns": 7183789.0,
          "max_time_ns": 7785304.0,
          "std_time_ns": 76950.51,
          "memory_bytes": 0,
          "allocs": 0,
          "samples": 669,
          "timestamp": "2025-11-21T04:15:57.257",
          "julia_version": "1.10.10"
        },
        "2": {...}
      }
    },
    "enzyme": {...}
  }
}
```

### 5. All Runs Index (`all_runs_index.json`)

Lightweight index for accessing all runs dynamically:

```json
{
  "version": "2.0",
  "generated_at": "2025-12-17T15:30:00.000",
  "groups": {
    "trixi": {
      "total_runs": 2547,
      "first_run_date": "2018-01-15",
      "last_run_date": "2025-12-17",
      "runs": [
        {
          "run": 1,
          "date": "2018-01-15",
          "timestamp": "2018-01-15T04:15:57.257",
          "julia_version": "0.6.2",
          "commit_hash": "abc123...",
          "benchmark_count": 42,
          "url": "by_group/trixi/run_1.json"
        },
        ...
      ]
    }
  }
}
```

### 6. Markdown Report (`by_date/YYYY-MM-DD/report.md`)

Human-readable report with:
- Run metadata (date, Julia version, commit)
- Summary statistics
- Comparison with previous run (if available)
- Top 10 fastest/slowest benchmarks
- Regression warnings

Example:
```markdown
# Benchmark Report - 2025-12-17

## Metadata
- **Date**: 2025-12-17 15:30:00
- **Julia Version**: 1.11.5
- **Commit**: abc123...

## Trixi.jl Benchmarks

Run #5 (42 benchmarks)

### Comparison with Previous Run (#4)

| Benchmark | Current (ms) | Previous (ms) | Change |
|-----------|--------------|---------------|--------|
| tree_2d_dgsem/.../p7_rhs! | 7.53 | 7.46 | +0.9% ⚠️ |
| ... | ... | ... | ... |

### Top 10 Slowest Benchmarks
1. tree_3d_dgsem/.../p7_rhs! - 245.3 ms
2. ...

## Enzyme.jl Benchmarks
...
```

## Advantages

1. **Fast Dashboard Loading**: `latest_100.json` loads instantly
2. **Full History Access**: `all_runs_index.json` + dynamic loading for complete history
3. **Efficient CI**: Small incremental files in gh-pages branch
4. **Historical Analysis**: Easy to load specific date ranges
5. **Human-Readable**: Markdown reports for GitHub viewing
6. **Scalable**: File size doesn't grow unbounded
7. **Flexible**: Can load by date, by run number, by group, or by commit hash
8. **Git Integration**: Direct lookup of benchmarks by commit hash
9. **Progressive Loading**: Start fast with recent data, load more on demand

## Implementation Notes

### CI Workflow Integration

When CI runs benchmarks:
1. Fetch existing data from gh-pages branch
2. Determine next run number from `index.json`
3. Run benchmarks
4. Save to:
   - `by_date/{today}/{group}.json`
   - `by_group/{group}/run_N.json`
   - `by_hash/{commit_hash}/{group}.json`
5. Update `index.json`
6. Regenerate `latest_100.json` (last 100 runs only)
7. Generate `report.md`
8. Commit and push to gh-pages branch

### API

```julia
history = load_history("data")
history = load_history("data", group="trixi")
save_benchmark_results(results, "trixi", data_dir="data", commit_hash="abc123")
update_index("data")

trixi_data = load_by_hash("e675a6f", "trixi")
all_data = load_by_hash("e675a6f")

generate_all_runs_index("data")
```
