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
    #joinpath(examples_dir(), "tree_2d_dgsem", "elixir_euler_vortex_mortar_shockcapturing.jl"),
    #joinpath(examples_dir(), "tree_2d_dgsem", "elixir_mhd_ec.jl"),
    #joinpath(examples_dir(), "structured_2d_dgsem", "elixir_advection_extended.jl"),
    #joinpath(examples_dir(), "structured_2d_dgsem", "elixir_advection_nonperiodic.jl"),
    #joinpath(examples_dir(), "structured_2d_dgsem", "elixir_euler_ec.jl"),
    #joinpath(examples_dir(), "structured_2d_dgsem", "elixir_euler_source_terms_nonperiodic.jl"),
    #joinpath(examples_dir(), "structured_2d_dgsem", "elixir_mhd_ec.jl"),
    #joinpath(examples_dir(), "unstructured_2d_dgsem", "elixir_euler_wall_bc.jl"),
    #joinpath(examples_dir(), "p4est_2d_dgsem", "elixir_advection_extended.jl"),
    
    # 3D
    #joinpath(examples_dir(), "tree_3d_dgsem", "elixir_advection_extended.jl"),
    #joinpath(examples_dir(), "tree_3d_dgsem", "elixir_euler_ec.jl"),
    #joinpath(examples_dir(), "tree_3d_dgsem", "elixir_euler_mortar.jl"),
    #joinpath(examples_dir(), "tree_3d_dgsem", "elixir_euler_shockcapturing.jl"),
    #joinpath(examples_dir(), "tree_3d_dgsem", "elixir_mhd_ec.jl"),
    #joinpath(examples_dir(), "structured_3d_dgsem", "elixir_advection_nonperiodic_curved.jl"),
    #joinpath(examples_dir(), "structured_3d_dgsem", "elixir_euler_ec.jl"),
    #joinpath(examples_dir(), "structured_3d_dgsem", "elixir_euler_source_terms_nonperiodic_curved.jl"),
    #joinpath(examples_dir(), "structured_3d_dgsem", "elixir_mhd_ec.jl"),
    #joinpath(examples_dir(), "p4est_3d_dgsem", "elixir_advection_basic.jl"),
]
    benchname = basename(dirname(elixir)) * "/" * basename(elixir)
    SUITE[benchname] = BenchmarkGroup()
    for polydeg in [3, 7]
        trixi_include(elixir, tspan=(0.0, 1.0e-10); polydeg)
        SUITE[benchname]["p$(polydeg)_rhs!"] = @benchmarkable Trixi.rhs!(
            $(similar(sol.u[end])), $(copy(sol.u[end])), $(semi), $(first(tspan)))
        SUITE[benchname]["p$(polydeg)_analysis"] = @benchmarkable ($analysis_callback)($sol)
    end
end
