@testset "Import Scripts" begin
    @testset "import script exists and loads" begin
        script_path = joinpath(@__DIR__, "../scripts/import_github_benchmark.jl")
        @test isfile(script_path)

        mod = Module(:ImportScriptTest)
        try
            Base.include(mod, script_path)
            @test isdefined(mod, :import_github_benchmark)
        catch e
            @test false
        end
    end
end
