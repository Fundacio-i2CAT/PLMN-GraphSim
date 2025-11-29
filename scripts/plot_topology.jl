using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using DesJulia6gRupa
using DesJulia6gRupa.Plotting

function plot_all_operators()
    # Scale Factor for Plotting
    # Use a larger scale factor (fewer points) for plotting to keep it clean and fast
    # 1:1000 is reasonable (~40,000 points)
    SCALE = 1000

    # Scenario 1: Centralized (3 UPFs)
    println("\n--- Plotting Centralized Scenario (3 UPFs) ---")
    # plot_operator_topology_with_cities("Vodafone", 1, 3, "Centralized"; scale_factor=SCALE)
    # plot_operator_topology_with_cities("Orange", 3, 3, "Centralized"; scale_factor=SCALE)
    # plot_operator_topology_with_cities("Movistar", 7, 3, "Centralized"; scale_factor=SCALE)
    
    # New Graph Visualization
    topology_vodafone = DesJulia6gRupa.DataLoading.load_and_deploy_network(joinpath(@__DIR__, "../data/214.csv"), 1, 3)
    plot_network_graph(topology_vodafone, "Vodafone", "Centralized")

    # Scenario 2: Distributed (50 UPFs)
    println("\n--- Plotting Distributed Scenario (50 UPFs) ---")
    # plot_operator_topology_with_cities("Vodafone", 1, 50, "Distributed"; scale_factor=SCALE)
    # plot_operator_topology_with_cities("Orange", 3, 50, "Distributed"; scale_factor=SCALE)
    # plot_operator_topology_with_cities("Movistar", 7, 50, "Distributed"; scale_factor=SCALE)

    topology_vodafone_dist = DesJulia6gRupa.DataLoading.load_and_deploy_network(joinpath(@__DIR__, "../data/214.csv"), 1, 50)
    plot_network_graph(topology_vodafone_dist, "Vodafone", "Distributed")
end

plot_all_operators()
