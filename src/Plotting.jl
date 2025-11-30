module Plotting

using Plots
using CSV
using DataFrames
using Clustering
using Random
using Graphs
using MetaGraphsNext
using ..Types

export plot_topology_map, plot_network_graph

# Helper for limits
function calculate_plot_limits(points::Vector{GeoPoint}, buffer_percent::Float64=0.05)
    if isempty(points)
        return (35.0, 44.0), (-10.0, 5.0) # Default fallback
    end
    
    min_lat, max_lat = 90.0, -90.0
    min_lon, max_lon = 180.0, -180.0

    for p in points
        min_lat = min(min_lat, p.lat)
        max_lat = max(max_lat, p.lat)
        min_lon = min(min_lon, p.lon)
        max_lon = max(max_lon, p.lon)
    end

    lat_buf = (max_lat - min_lat) * buffer_percent
    lon_buf = (max_lon - min_lon) * buffer_percent
    
    return (min_lat - lat_buf, max_lat + lat_buf), (min_lon - lon_buf, max_lon + lon_buf)
end

function plot_topology_map(
    topology::NetworkTopology,
    operator_name::String,
    scenario_name::String;
    agent_locations::Vector{GeoPoint} = GeoPoint[],
    cities::Vector{Tuple{String, GeoPoint}} = Tuple{String, GeoPoint}[],
    output_dir::String = joinpath(@__DIR__, "../images")
)
    println("Plotting for $operator_name ($scenario_name)...")
    
    # Determine Plot Limits from Data
    # Use municipalities bounding box if available, else gNBs
    points_for_limits = !isempty(topology.municipalities) ? [m.location for m in topology.municipalities] : topology.gnb_locations
    ylims_val, xlims_val = calculate_plot_limits(points_for_limits)

    # Custom Ticks (User request: Latitude steps of 2)
    lat_step = 2.0
    lat_start = floor(ylims_val[1] / lat_step) * lat_step
    lat_stop = ceil(ylims_val[2] / lat_step) * lat_step
    yticks_val = lat_start:lat_step:lat_stop

    p = plot(
        title="6G-RUPA Topology: $operator_name - $scenario_name",
        xlabel="Longitude",
        ylabel="Latitude",
        legend=:outertopright,
        size=(2400, 2000), # Increased resolution (2x dimensions)
        dpi=300,           # High DPI for zooming
        aspect_ratio=:equal,
        ylims=ylims_val,
        xlims=xlims_val,
        yticks=yticks_val,
        titlefontsize=24,
        guidefontsize=18,
        tickfontsize=14,
        legendfontsize=16
    )
    
    gnb_lons = [p.lon for p in topology.gnb_locations]
    gnb_lats = [p.lat for p in topology.gnb_locations]
    
    scatter!(p, gnb_lons, gnb_lats,
        label="gNBs",
        markersize=1.5,
        markercolor=:orange,
        markeralpha=0.3,
        markerstrokewidth=0
    )
    
    if !isempty(agent_locations)
        agent_lons = [p.lon for p in agent_locations]
        agent_lats = [p.lat for p in agent_locations]
        scatter!(p, agent_lons, agent_lats,
            label="Users (Agents)",
            markersize=1.5,
            markercolor=:blue,
            markeralpha=0.6,
            markerstrokewidth=0
        )
    end
    
    num_upfs = length(topology.upf_locations)
    upf_lons = [p.lon for p in topology.upf_locations]
    upf_lats = [p.lat for p in topology.upf_locations]
    
    scatter!(p, upf_lons, upf_lats,
        label="UPFs ($num_upfs Hubs)",
        markersize=7,
        markercolor=:red,
        markershape=:square,
        markerstrokewidth=1
    )

    # Annotate UPFs with their ID
    annotate!(p, [(upf_lons[i], upf_lats[i], text(string(i), 16, :white, :center)) for i in 1:length(upf_lons)])

    if !isempty(cities)
        city_lons = [c[2].lon for c in cities]
        city_lats = [c[2].lat for c in cities]
        city_names = [c[1] for c in cities]

        scatter!(p, city_lons, city_lats,
            label="Major Cities",
            markersize=5,
            markercolor=:green,
            markershape=:star5,
            markerstrokewidth=1
        )

        # Annotate Cities
        # Use smaller font (6) and slightly larger offset to reduce overlap
        annotate!(p, [(city_lons[i], city_lats[i] + 0.15, text(city_names[i], 14, :black, :bottom)) for i in 1:length(cities)])
    end

    # Save
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    output_filename = "topology_map_cities_$(lowercase(operator_name))_$(lowercase(scenario_name)).png"
    output_path = joinpath(output_dir, output_filename)
    savefig(p, output_path)
    println("Plot saved to $output_path")
end

function plot_network_graph(
    topology::NetworkTopology, 
    operator_name::String, 
    scenario_name::String;
    output_dir::String = joinpath(@__DIR__, "../images")
)
    println("Generating Graph Visualization for $operator_name...")
    
    # Determine Plot Limits from Data
    ylims_val, xlims_val = calculate_plot_limits(topology.gnb_locations)

    p = plot(
        title="6G-RUPA Network Graph: $operator_name",
        xlabel="Longitude",
        ylabel="Latitude",
        legend=false,
        size=(2400, 2000),
        dpi=300,
        aspect_ratio=:equal,
        ylims=ylims_val,
        xlims=xlims_val,
        titlefontsize=24,
        guidefontsize=18,
        tickfontsize=14
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
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    output_filename = "graph_viz_$(lowercase(operator_name))_$(lowercase(scenario_name)).png"
    output_path = joinpath(output_dir, output_filename)
    savefig(p, output_path)
    println("Graph visualization saved to $output_path")
end

end
