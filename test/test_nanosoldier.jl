@testset "Nanosoldier Import" begin
    script_path = joinpath(@__DIR__, "../scripts/import_nanosoldier.jl")
    mod = Module(:NanosoldierTestModule)
    Base.include(mod, script_path)

    @testset "script exists and loads" begin
        @test isfile(script_path)
        @test isdefined(mod, :parse_report_md)
        @test isdefined(mod, :convert_to_explorer_format)
    end

    @testset "parse_report_md" begin
        test_content = """
        # Benchmark Report

        **Regressions:**
        - `["inference", "sin"]`: 1.5x slower
        - `["array", "sum"]`: 2.0x slower

        **Improvements:**
        - `["math", "cos"]`: 0.8x faster
        """

        results = Base.invokelatest(mod.parse_report_md, test_content)

        @test haskey(results, "[\"inference\", \"sin\"]")
        @test results["[\"inference\", \"sin\"]"]["time_ratio"] == 1.5

        @test haskey(results, "[\"array\", \"sum\"]")
        @test results["[\"array\", \"sum\"]"]["time_ratio"] == 2.0

        @test haskey(results, "[\"math\", \"cos\"]")
        @test results["[\"math\", \"cos\"]"]["time_ratio"] == 0.8
    end

    @testset "convert_to_explorer_format" begin
        safe_mktempdir() do temp_dir
            nano_dir = joinpath(temp_dir, "nanosoldier")
            output_dir = joinpath(temp_dir, "output")
            mkpath(nano_dir)

            test_data = Dict(
                "metadata" => Dict(
                    "head_hash" => "abc123",
                    "base_hash" => "def456",
                    "imported_at" => "2026-01-01T10:00:00"
                ),
                "benchmarks" => Dict(
                    "[\"test\", \"bench1\"]" => Dict("time_ratio" => 1.5, "memory_ratio" => 1.0),
                    "[\"test\", \"bench2\"]" => Dict("time_ratio" => 0.8, "memory_ratio" => 1.0)
                )
            )

            open(joinpath(nano_dir, "test_comparison.json"), "w") do f
                JSON.print(f, test_data)
            end

            Base.invokelatest(mod.convert_to_explorer_format, nano_dir, output_dir, "testgroup")

            @test isfile(joinpath(output_dir, "by_group", "testgroup", "history.json"))
            @test isfile(joinpath(output_dir, "latest_100.json"))
            @test isfile(joinpath(output_dir, "index.json"))

            latest = JSON.parsefile(joinpath(output_dir, "latest_100.json"))
            @test haskey(latest, "groups")
            @test haskey(latest["groups"], "testgroup")

            index = JSON.parsefile(joinpath(output_dir, "index.json"))
            @test haskey(index, "groups")
            @test haskey(index, "version")
            @test index["version"] == "2.0"

            has_testgroup = false
            for key in keys(index["groups"])
                if startswith(key, "testgroup")
                    has_testgroup = true
                    group_info = index["groups"][key]
                    @test haskey(group_info, "total_runs")
                    @test haskey(group_info, "latest_run")
                    @test haskey(group_info, "runs")
                    @test group_info["total_runs"] == 1
                end
            end
            @test has_testgroup
        end
    end

    @testset "convert_to_explorer_format categories" begin
        safe_mktempdir() do temp_dir
            nano_dir = joinpath(temp_dir, "nanosoldier")
            output_dir = joinpath(temp_dir, "output")
            mkpath(nano_dir)

            test_data = Dict(
                "metadata" => Dict(
                    "head_hash" => "abc123",
                    "base_hash" => "def456",
                    "imported_at" => "2026-01-01T10:00:00"
                ),
                "benchmarks" => Dict(
                    "[\"inference\", \"sin\"]" => Dict("time_ratio" => 1.5, "memory_ratio" => 1.0),
                    "[\"inference\", \"cos\"]" => Dict("time_ratio" => 0.9, "memory_ratio" => 1.0),
                    "[\"array\", \"sum\"]" => Dict("time_ratio" => 2.0, "memory_ratio" => 1.0)
                )
            )

            open(joinpath(nano_dir, "comp1.json"), "w") do f
                JSON.print(f, test_data)
            end

            Base.invokelatest(mod.convert_to_explorer_format, nano_dir, output_dir, "ns")

            latest = JSON.parsefile(joinpath(output_dir, "latest_100.json"))
            groups = keys(latest["groups"])

            @test "ns" in groups
            @test any(g -> startswith(g, "ns_"), groups)

            @test isdir(joinpath(output_dir, "by_group", "ns"))
            @test isfile(joinpath(output_dir, "by_group", "ns", "history.json"))
        end
    end
end
