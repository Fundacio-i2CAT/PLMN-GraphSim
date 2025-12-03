using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using DesJulia6gRupa
using DesJulia6gRupa.Plotting

function plot_usa_topology()
    # Scale Factor for Plotting
    # USA is huge, so we might need a larger scale factor or just accept it takes time.
    # Population is ~335M. 1:1000 -> 335k agents. That's a lot for plotting.
    # Let's use 1:10000 -> 33.5k agents.
    SCALE = 10000

    println("\n--- Plotting USA Topology (Verizon - MNC 480) ---")
    
    # We use data_dir pointing to USA data
    # Operator ID 480 (Verizon)
    # 50 UPFs (Distributed)
    
    data_dir = joinpath(@__DIR__, "../data/usa")
    plot_operator_topology_with_cities("Verizon", 480, 50, "Distributed"; scale_factor=SCALE, data_dir=data_dir)
    
    # Also plot the graph
    # Note: We need to manually call load_and_deploy_network with data_dir
    # topology = DesJulia6gRupa.DataLoading.load_and_deploy_network(joinpath(data_dir, "opencellid/311.csv"), 480, 50, data_dir)
    # plot_network_graph(topology, "Verizon", "Distributed")
end

plot_usa_topology()
