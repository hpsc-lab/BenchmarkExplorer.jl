using Test
using BenchmarkExplorer
using JSON
using BenchmarkTools
using Dates

function safe_mktempdir(f)
    dir = mktempdir()
    try
        f(dir)
    finally
        GC.gc()
        if Sys.iswindows()
            sleep(0.5)
            GC.gc()
            for attempt in 1:5
                try
                    rm(dir, recursive=true, force=true)
                    break
                catch
                    sleep(0.2 * attempt)
                    GC.gc()
                end
            end
        else
            rm(dir, recursive=true, force=true)
        end
    end
end

@testset "BenchmarkExplorer.jl" begin
    include("test_benchmark_ui.jl")
    include("test_history_manager.jl")
    include("test_dashboards.jl")
    include("test_import.jl")
    include("test_conversion.jl")
    include("test_extended_fields.jl")
    include("test_error_handling.jl")
    include("test_markdown_report.jl")
end
