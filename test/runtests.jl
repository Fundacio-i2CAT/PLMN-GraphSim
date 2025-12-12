using Test
using DesJulia6gRupa

@testset "DesJulia6gRupa.jl" begin
    include("AgentGenerationTests.jl")
    include("SimulationTests.jl")
    include("TwoTierTests.jl")
    include("IntegrationTests.jl")
    
    if Base.find_package("Aqua") !== nothing && Base.find_package("JET") !== nothing
        include("qa.jl")
    else
        @info "Skipping QA tests (Aqua/JET not found). Run `Pkg.test()` to include them."
    end
end
