# Contributing to BenchmarkExplorer.jl

Thank you for your interest in contributing!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/BenchmarkExplorer.jl.git`
3. Create a branch: `git checkout -b feature/your-feature`

## Development Setup

```julia
using Pkg
Pkg.develop(path=".")
Pkg.test("BenchmarkExplorer")
```

## Making Changes

1. Make your changes
2. Add tests for new functionality
3. Run tests: `julia --project=. -e 'using Pkg; Pkg.test()'`
4. Commit with clear messages

## Pull Request Process

1. Update documentation if needed
2. Ensure all tests pass
3. Submit PR against `main` branch
4. Wait for review

## Code Style

- Follow Julia conventions
- Use meaningful variable names
- Add docstrings for public functions

## Reporting Bugs

Use GitHub Issues with:
- Clear description
- Steps to reproduce
- Expected vs actual behavior
- Julia version and OS

## Questions?

Open an issue or discussion.
