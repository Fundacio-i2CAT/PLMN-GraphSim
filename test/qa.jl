using Test
using Aqua
using JET
using DesJulia6gRupa

@testset "QA" begin
    # Aqua.jl: Auto Quality Assurance for Julia packages
    @testset "Aqua" begin
        Aqua.test_all(DesJulia6gRupa; ambiguities=false)
    end

    # JET.jl: Code analyzer for Julia (type checking)
    @testset "JET" begin
        JET.test_package(DesJulia6gRupa; target_defined_modules=true)
    end
end
