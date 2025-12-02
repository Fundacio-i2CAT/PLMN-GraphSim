module Plotting

using ..Types

export plot_topology_map, plot_network_graph

function plot_topology_map(args...; kwargs...)
    # This function is implemented in the DesJulia6gRupaPlottingExt extension.
    # It requires the Plots package to be loaded.
    @warn "Plotting functionality requires the Plots package. Please run `using Plots` to enable it."
end

function plot_network_graph(args...; kwargs...)
    # This function is implemented in the DesJulia6gRupaPlottingExt extension.
    # It requires the Plots package to be loaded.
    @warn "Plotting functionality requires the Plots package. Please run `using Plots` to enable it."
end

end
