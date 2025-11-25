using Pkg
Pkg.activate(dirname(@__DIR__))

include("run_trixi.jl")
include("run_enzyme.jl")

function run_all_benchmarks()
    
    try
        run_and_save_trixi()
    catch e
        println("Trixi benchmarks failed: $e")
    end
    
    try
        run_and_save_enzyme()
    catch e
        println("Enzyme benchmarks failed: $e")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_all_benchmarks()
end
