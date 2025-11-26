using Pkg
Pkg.activate(dirname(@__DIR__))

include("run_all.jl")

function populate_history(n_runs=5)
    
    for i in 1:n_runs
        run_all_benchmarks()
        if i < n_runs
            sleep(2)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    n_runs = length(ARGS) > 0 ? parse(Int, ARGS[1]) : 5
    populate_history(n_runs)
end
