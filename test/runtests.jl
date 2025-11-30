using Test
using DesJulia6gRupa

@testset "DesJulia6gRupa.jl" begin
    include("AgentGenerationTests.jl")
    include("SimulationTests.jl")
    include("IntegrationTests.jl")
end
