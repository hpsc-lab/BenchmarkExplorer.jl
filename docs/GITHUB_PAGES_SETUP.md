# GitHub Pages Setup

Enable GitHub Pages for online benchmark results.

## Setup

1. Go to repository Settings → Pages
2. Set Source: `gh-pages` branch, `/ (root)` folder
3. Save

## How It Works

Workflow sequence:

1. `benchmarks.yml` runs benchmarks, generates HTML pages, pushes to `gh-pages`
2. `pages.yml` deploys `gh-pages` content to GitHub Pages

Generated pages:
- `index.html` - main dashboard with all benchmark groups
- `{group}.html` - individual group pages with Chart.js visualizations

## Access

Results available at:
```
https://username.github.io/repo/
```

## Local Preview

Generate pages locally:

```bash
mkdir -p /tmp/preview
cp data/history_*.json /tmp/preview/

julia ci/generate_index_page.jl /tmp/preview /tmp/preview/index.html \
  "https://github.com/username/repo" "$(git rev-parse HEAD)"

julia ci/generate_static_page.jl /tmp/preview/history.json \
  /tmp/preview/group.html group "https://github.com/username/repo" "$(git rev-parse HEAD)"

xdg-open /tmp/preview/index.html
```

## Customization

Edit generator scripts:
- `ci/generate_index_page.jl` - main index page
- `ci/generate_static_page.jl` - group pages

Both use inline CSS for easy styling.

## Troubleshooting

Pages not updating:
- Check Actions tab for workflow status
- Verify `gh-pages` branch exists
- Wait 1-2 minutes for deployment

404 error:
- Verify source is `gh-pages` branch, not `main`
- Check files exist in `gh-pages` branch

Permission denied:
```yaml
permissions:
  contents: write
  pages: write
  id-token: write
```

## Notes

- GitHub Pages updates take 1-2 minutes
- Pages are public even for private repos
- History stored in `gh-pages` indefinitely
- Each CI run adds incremental data
