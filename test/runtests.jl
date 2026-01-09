using Test
using BenchmarkExplorer
using JSON
using BenchmarkTools
using Dates

@testset "BenchmarkExplorer.jl" begin
    include("test_benchmark_ui.jl")
    include("test_history_manager.jl")
    include("test_dashboards.jl")
    include("test_import.jl")
    include("test_conversion.jl")
end
