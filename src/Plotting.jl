module Plotting

using Plots
using CSV
using DataFrames
using Clustering
using Random
using Graphs
using MetaGraphsNext
using ..Types
using ..DataLoading
using ..AgentGeneration

export plot_operator_topology_with_cities, plot_network_graph

function plot_operator_topology_with_cities(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String; scale_factor::Int=1000)
    csv_path = joinpath(@__DIR__, "../data/214.csv")

    if !isfile(csv_path)
        error("Data file not found at $csv_path")
    end

    # 1. Get Data (Using unified topology loader)
    topology = load_and_deploy_network(csv_path, operator_id, num_upfs)

    if isempty(topology.gnb_locations)
        println("No data for $operator_name. Skipping.")
        return
    end

    # 2. Generate Agents (Using unified AgentGeneration)
    num_agents = ceil(Int, EFFECTIVE_POPULATION / scale_factor)
    println("Generating $num_agents agents using population density (Scale: 1:$scale_factor)...")
    
    # Limit plotting if too many agents (e.g. > 100k) to avoid crashing plots
    if num_agents > 100000
        println("Warning: Too many agents ($num_agents). Capping at 100,000 for plotting.")
        num_agents = 100000
    end

    agent_locs = generate_agent_locations(topology, num_agents)

    agent_lons = [p.lon for p in agent_locs]
    agent_lats = [p.lat for p in agent_locs]

    # Extract gNB and UPF coords for plotting
    gnb_lons = [p.lon for p in topology.gnb_locations]
    gnb_lats = [p.lat for p in topology.gnb_locations]

    upf_lons = [p.lon for p in topology.upf_locations]
    upf_lats = [p.lat for p in topology.upf_locations]

    println("Plotting for $operator_name ($scenario_name)...")
    p = plot(
        title="6G-RUPA Topology: $operator_name - $scenario_name",
        xlabel="Longitude",
        ylabel="Latitude",
        legend=:outertopright,
        size=(1200, 1000),
        aspect_ratio=:equal,
        ylims=(35, 44)
    )
    scatter!(p, gnb_lons, gnb_lats,
        label="gNBs",
        markersize=1.5,
        markercolor=:orange,
        markeralpha=0.3,
        markerstrokewidth=0
    )
    scatter!(p, agent_lons, agent_lats,
        label="Users (Agents)",
        markersize=1.5,
        markercolor=:blue,
        markeralpha=0.6,
        markerstrokewidth=0
    )
    scatter!(p, upf_lons, upf_lats,
        label="UPFs ($num_upfs Hubs)",
        markersize=7,
        markercolor=:red,
        markershape=:square,
        markerstrokewidth=1
    )

    # Annotate UPFs with their ID
    annotate!(p, [(upf_lons[i], upf_lats[i], text(string(i), 8, :white, :center)) for i in 1:length(upf_lons)])

    # 3. Plot Reference Cities - Green Stars
    city_lons = [c[2].lon for c in REFERENCE_CITIES]
    city_lats = [c[2].lat for c in REFERENCE_CITIES]
    city_names = [c[1] for c in REFERENCE_CITIES]

    scatter!(p, city_lons, city_lats,
        label="Major Cities",
        markersize=5,
        markercolor=:green,
        markershape=:star5,
        markerstrokewidth=1
    )

    # Annotate Cities
    annotate!(p, [(city_lons[i], city_lats[i] + 0.1, text(city_names[i], 8, :black, :bottom)) for i in 1:length(REFERENCE_CITIES)])

    # Save
    output_dir = joinpath(@__DIR__, "../images")
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    output_filename = "topology_map_cities_$(lowercase(operator_name))_$(lowercase(scenario_name)).png"
    output_path = joinpath(output_dir, output_filename)
    savefig(p, output_path)
    println("Plot saved to $output_path")
end

"""
    plot_network_graph(topology::NetworkTopology, operator_name::String, scenario_name::String)

Visualizes the network graph structure.
- Draws lines between gNBs and their assigned UPFs.
- Color-codes clusters (each UPF + connected gNBs = one color).
- Shows the "forest of trees" structure.
"""
function plot_network_graph(topology::NetworkTopology, operator_name::String, scenario_name::String)
    println("Generating Graph Visualization for $operator_name...")
    
    p = plot(
        title="6G-RUPA Network Graph: $operator_name",
        xlabel="Longitude",
        ylabel="Latitude",
        legend=false,
        size=(1200, 1000),
        aspect_ratio=:equal,
        ylims=(35, 44)
    )

    # 1. Draw Edges (gNB <-> UPF)
    # We use the NaN separator technique for fast plotting of many segments
    # We will group them by UPF to color-code the clusters
    
    num_upfs = length(topology.upf_locations)
    colors = distinguishable_colors(num_upfs + 2, [colorant"white", colorant"black"])
    # Drop white/black to ensure visibility
    cluster_colors = colors[3:end]

    println("  Drawing connections for $num_upfs clusters...")

    for upf_idx in 1:num_upfs
        upf_loc = topology.upf_locations[upf_idx]
        
        # Find all gNBs connected to this UPF
        # We can use the map for speed, or the graph. Let's use the map as it's O(1) lookup per gNB
        connected_gnb_indices = findall(x -> x == upf_idx, topology.gnb_to_upf_map)
        
        if isempty(connected_gnb_indices)
            continue
        end

        # Build coordinate vectors with NaN separators
        # [upf_x, gnb1_x, NaN, upf_x, gnb2_x, NaN, ...]
        seg_lons = Float64[]
        seg_lats = Float64[]
        
        for gnb_idx in connected_gnb_indices
            gnb_loc = topology.gnb_locations[gnb_idx]
            push!(seg_lons, upf_loc.lon, gnb_loc.lon, NaN)
            push!(seg_lats, upf_loc.lat, gnb_loc.lat, NaN)
        end

        # Plot this cluster's edges
        plot!(p, seg_lons, seg_lats, 
            linecolor=cluster_colors[upf_idx], 
            linewidth=0.5, 
            alpha=0.6
        )
    end

    # 2. Plot Nodes
    gnb_lons = [p.lon for p in topology.gnb_locations]
    gnb_lats = [p.lat for p in topology.gnb_locations]
    upf_lons = [p.lon for p in topology.upf_locations]
    upf_lats = [p.lat for p in topology.upf_locations]

    scatter!(p, gnb_lons, gnb_lats,
        label="gNBs",
        markersize=2,
        markercolor=:grey,
        markeralpha=0.5,
        markerstrokewidth=0
    )

    scatter!(p, upf_lons, upf_lats,
        label="UPFs",
        markersize=6,
        markercolor=:black,
        markershape=:rect,
        markerstrokewidth=1
    )

    # Save
    output_dir = joinpath(@__DIR__, "../images")
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    output_filename = "graph_viz_$(lowercase(operator_name))_$(lowercase(scenario_name)).png"
    output_path = joinpath(output_dir, output_filename)
    savefig(p, output_path)
    println("Graph visualization saved to $output_path")
end

end
