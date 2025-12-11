# Migration Guide for trixi-performance-tracker

How to adapt https://github.com/vchuravy/trixi-performance-tracker to generate BenchmarkExplorer JSON format.

## What to change

You need to modify 3 places in `.github/workflows/Nightly.yml`:

### 1. Lines 39-41: Generate JSON instead of markdown

Replace the benchmark run step with code that generates BenchmarkExplorer format:

```yaml
- name: Run benchmarks and save history
  run: |
    julia --project -e '
      using Pkg; Pkg.instantiate()
      using BenchmarkTools, JSON, Dates, Statistics

      include("benchmarks/benchmarks.jl")

      results = run(SUITE, verbose=true)

      # Flatten nested groups into paths
      function flatten_benchmarks(group, path=String[])
        flat = Dict{String, BenchmarkTools.Trial}()
        for (key, value) in group
          current_path = [path..., string(key)]
          if value isa BenchmarkTools.Trial
            flat[join(current_path, "/")] = value
          elseif value isa BenchmarkTools.BenchmarkGroup
            merge!(flat, flatten_benchmarks(value, current_path))
          end
        end
        return flat
      end

      history_file = "benchmark_history.json"
      history = isfile(history_file) ? JSON.parsefile(history_file) : Dict()

      flat_benchmarks = flatten_benchmarks(results)
      for (name, trial) in flat_benchmarks
        if !haskey(history, name)
          history[name] = Dict()
        end

        runs = keys(history[name])
        next_run = isempty(runs) ? 1 : maximum(parse(Int, k) for k in runs) + 1

        history[name][string(next_run)] = Dict(
          "mean_time_ns" => mean(trial).time,
          "min_time_ns" => minimum(trial).time,
          "median_time_ns" => median(trial).time,
          "max_time_ns" => maximum(trial).time,
          "std_time_ns" => std(trial.times),
          "memory_bytes" => trial.memory,
          "allocs" => trial.allocs,
          "timestamp" => string(now()),
          "samples" => length(trial.times),
          "julia_version" => string(VERSION)
        )
      end

      open(history_file, "w") do f
        JSON.print(f, history, 2)
      end

      println("Saved $(length(flat_benchmarks)) benchmarks to $history_file")
    '
```

### 2. Lines 42-55: Publish to gh-pages instead of main

Replace the commit/push step to save results in seperate branch:

```yaml
- name: Fetch history from gh-pages
  run: |
    git fetch origin gh-pages || echo "gh-pages doesnt exist yet"
    git show origin/gh-pages:benchmark_history.json > benchmark_history.json 2>/dev/null || echo "{}" > benchmark_history.json

- name: Publish to gh-pages
  run: |
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"

    git fetch origin gh-pages || true
    git checkout gh-pages || git checkout --orphan gh-pages

    # Clean everything except history file
    find . -maxdepth 1 ! -name '.git' ! -name 'benchmark_history.json' ! -name '.' -exec rm -rf {} +

    # Simple index page
    cat > index.html << 'EOF'
    <!DOCTYPE html>
    <html>
    <head><title>Trixi Benchmarks</title></head>
    <body>
      <h1>Trixi Performance Tracker</h1>
      <p>Last updated: $(date -u +"%Y-%m-%d %H:%M")</p>
      <p><a href="benchmark_history.json">Download JSON</a></p>
      <p>Use BenchmarkExplorer dashboard to visualize</p>
    </body>
    </html>
    EOF

    git add -A
    git commit -m "Update benchmarks for ${{ github.sha }}" || echo "No changes"
    git push origin gh-pages

    git checkout ${{ github.sha }}
```

### 3. Lines 2-7: Triggers (optional)

Can keep as is or add workflow_dispatch for manual runs:

```yaml
on:
  schedule:
    - cron: '0 2 * * *'
  workflow_dispatch:
```

## Using the action

Alternative: use reusable action instead of inline code:

```yaml
jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hpsc-lab/BenchmarkExplorer.jl@main
        with:
          benchmark_script: 'benchmarks/benchmarks.jl'
          history_file: 'benchmark_history.json'
          group_name: 'trixi'
```

## Viewing results

After setup:

1. Enable GitHub Pages in repo settings (source: gh-pages branch)
2. Results avalable at `https://vchuravy.github.io/trixi-performance-tracker/`
3. Or download JSON and use dashboard locally:
   ```bash
   git clone https://github.com/hpsc-lab/BenchmarkExplorer.jl
   cd BenchmarkExplorer.jl
   wget https://vchuravy.github.io/trixi-performance-tracker/benchmark_history.json -O data/history.json
   julia dashboard.jl
   ```

## Notes

- History accumulates in gh-pages branch (run 1, 2, 3...)
- Each run adds incremental results with timestamp
- Compatible with BenchmarkExplorer dashboard out of the box
- No polution of main branch with large JSON files
