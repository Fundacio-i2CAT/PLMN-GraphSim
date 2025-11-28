module DesJulia6gRupa

include("Types.jl")
include("DataLoading.jl")
include("AgentGeneration.jl")
include("Simulation.jl")
include("Plotting.jl")

using .Types
using .DataLoading
using .AgentGeneration
using .Simulation
using .Plotting

export Types, DataLoading, AgentGeneration, Simulation, Plotting

end
