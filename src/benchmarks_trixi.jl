using BenchmarkTools
using Trixi

const SUITE = BenchmarkGroup()

for elixir in [
    # 1D
    joinpath(examples_dir(), "structured_1d_dgsem", "elixir_euler_sedov.jl"),
    joinpath(examples_dir(), "tree_1d_dgsem", "elixir_mhd_ec.jl"), 
   
    # 2D
    joinpath(examples_dir(), "tree_2d_dgsem", "elixir_advection_extended.jl"),
    joinpath(examples_dir(), "tree_2d_dgsem", "elixir_advection_amr_nonperiodic.jl"),
    joinpath(examples_dir(), "tree_2d_dgsem", "elixir_euler_ec.jl"),
    joinpath(examples_dir(), "tree_2d_dgsem", "elixir_euler_vortex_mortar.jl"),
]
    benchname = basename(dirname(elixir)) * "/" * basename(elixir)
    
    for polydeg in [3, 7]
        trixi_include(elixir, tspan=(0.0, 1.0e-10); polydeg)
        
        bench_path_rhs = "$benchname/p$(polydeg)_rhs!"
        bench_path_analysis = "$benchname/p$(polydeg)_analysis"
        
        SUITE[bench_path_rhs] = @benchmarkable Trixi.rhs!(
            $(similar(sol.u[end])), $(copy(sol.u[end])), $(semi), $(first(tspan))
        )
        
        SUITE[bench_path_analysis] = @benchmarkable ($analysis_callback)($sol)
    end
end