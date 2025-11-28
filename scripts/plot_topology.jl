using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using DesJulia6gRupa
using DesJulia6gRupa.Plotting

function plot_all_operators()
    # Scenario 1: Centralized (3 UPFs)
    println("\n--- Plotting Centralized Scenario (3 UPFs) ---")
    plot_operator_topology_with_cities("Vodafone", 1, 3, "Centralized")
    plot_operator_topology_with_cities("Orange", 3, 3, "Centralized")
    plot_operator_topology_with_cities("Movistar", 7, 3, "Centralized")

    # Scenario 2: Distributed (50 UPFs)
    println("\n--- Plotting Distributed Scenario (50 UPFs) ---")
    plot_operator_topology_with_cities("Vodafone", 1, 50, "Distributed")
    plot_operator_topology_with_cities("Orange", 3, 50, "Distributed")
    plot_operator_topology_with_cities("Movistar", 7, 50, "Distributed")
end

plot_all_operators()
