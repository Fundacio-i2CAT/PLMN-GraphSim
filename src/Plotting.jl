module Plotting

using ..Types

export plot_topology_map, plot_network_graph

function plot_topology_map(
    topology::NetworkTopology,
    operator_name::String,
    scenario_name::String;
    agent_locations::Vector{GeoPoint} = GeoPoint[],
    cities::Vector{Tuple{String, GeoPoint}} = Tuple{String, GeoPoint}[],
    output_dir::String = joinpath(@__DIR__, "../images")
)
    # This function is implemented in the DesJulia6gRupaPlottingExt extension.
    # It requires the Plots package to be loaded.
    @warn "Plotting functionality requires the Plots package. Please run `using Plots` to enable it."
end

function plot_network_graph(
    topology::NetworkTopology, 
    operator_name::String, 
    scenario_name::String;
    output_dir::String = joinpath(@__DIR__, "../images")
)
    # This function is implemented in the DesJulia6gRupaPlottingExt extension.
    # It requires the Plots package to be loaded.
    @warn "Plotting functionality requires the Plots package. Please run `using Plots` to enable it."
end

end
