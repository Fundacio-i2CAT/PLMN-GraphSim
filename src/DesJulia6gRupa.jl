module DesJulia6gRupa

include("Types.jl")
include("DataLoading.jl")
include("Simulation.jl")
include("Plotting.jl")

using .Types
using .DataLoading
using .Simulation
using .Plotting

export Types, DataLoading, Simulation, Plotting

end
