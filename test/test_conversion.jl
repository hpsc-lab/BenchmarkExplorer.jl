@testset "Conversion Scripts" begin
    @testset "conversion script exists and loads" begin
        script_path = joinpath(@__DIR__, "../scripts/convert_old_format.jl")
        @test isfile(script_path)

        try
            include(script_path)
            @test isdefined(Main, :convert_old_to_new)
        catch e
            @test false
        end
    end
end
