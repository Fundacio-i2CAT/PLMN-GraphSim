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

function plot_operator_topology_with_cities(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String; scale_factor::Int=1000, data_dir::String="", csv_path::String="")
    if isempty(data_dir)
        # Default to Spain for backward compatibility if not provided
        data_dir = joinpath(@__DIR__, "../data/spain")
    end

    # Resolve CSV Path if not provided
    if isempty(csv_path)
        opencellid_dir = joinpath(data_dir, "opencellid")
        if isdir(opencellid_dir)
            files = readdir(opencellid_dir)
            csv_files = filter(f -> endswith(f, ".csv"), files)
            if !isempty(csv_files)
                if isfile(joinpath(opencellid_dir, "214.csv"))
                    csv_path = joinpath(opencellid_dir, "214.csv")
                elseif isfile(joinpath(opencellid_dir, "311.csv"))
                    csv_path = joinpath(opencellid_dir, "311.csv")
                else
                    csv_path = joinpath(opencellid_dir, csv_files[1])
                end
            end
        end
    end

    if isempty(csv_path) || !isfile(csv_path)
        error("OpenCellID data file not found. Please provide valid csv_path or check data_dir.")
    end

    # 1. Get Data (Using unified topology loader)
    topology = load_and_deploy_network(csv_path, operator_id, num_upfs, data_dir)

    if isempty(topology.gnb_locations)
        println("No data for $operator_name. Skipping.")
        return
    end

    # 2. Generate Agents (Using unified AgentGeneration)
    # We need to know the population to scale correctly.
    # We can sum the population from the loaded municipalities in the topology!
    total_pop = sum([m.population for m in topology.municipalities])
    
    # Effective population ratio (using Spain constants as default, or we could put this in config)
    # Let's use the constants from Types.jl but apply them to the total_pop found.
    # Assuming demographics are roughly similar or we don't have better data.
    eff_pop = total_pop * (1 - RATIO_UNDER_15) * PHONE_ADOPTION_OVER_15
    
    num_agents = ceil(Int, eff_pop / scale_factor)
    println("Generating $num_agents agents using population density (Total Pop: $total_pop, Scale: 1:$scale_factor)...")
    
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
    
    # Determine Plot Limits from Data
    # Use municipalities bounding box if available, else gNBs
    min_lat, max_lat = 90.0, -90.0
    min_lon, max_lon = 180.0, -180.0
    
    if !isempty(topology.municipalities)
        for m in topology.municipalities
            min_lat = min(min_lat, m.location.lat)
            max_lat = max(max_lat, m.location.lat)
            min_lon = min(min_lon, m.location.lon)
            max_lon = max(max_lon, m.location.lon)
        end
    elseif !isempty(topology.gnb_locations)
        for p in topology.gnb_locations
            min_lat = min(min_lat, p.lat)
            max_lat = max(max_lat, p.lat)
            min_lon = min(min_lon, p.lon)
            max_lon = max(max_lon, p.lon)
        end
    end
    
    # Add buffer
    lat_buf = (max_lat - min_lat) * 0.05
    lon_buf = (max_lon - min_lon) * 0.05
    ylims_val = (min_lat - lat_buf, max_lat + lat_buf)
    xlims_val = (min_lon - lon_buf, max_lon + lon_buf)

    p = plot(
        title="6G-RUPA Topology: $operator_name - $scenario_name",
        xlabel="Longitude",
        ylabel="Latitude",
        legend=:outertopright,
        size=(1200, 1000),
        aspect_ratio=:equal,
        ylims=ylims_val,
        xlims=xlims_val
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
    cities_csv = joinpath(data_dir, "cities.csv")
    cities = []
    if isfile(cities_csv)
        cities_df = CSV.read(cities_csv, DataFrame)
        cities = [(row.name, GeoPoint(row.lat, row.lon)) for row in eachrow(cities_df)]
    else
        # Fallback to hardcoded Spain cities if file missing and we are in Spain context?
        # Or just warn.
        println("Warning: Cities file not found at $cities_csv")
    end

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
        annotate!(p, [(city_lons[i], city_lats[i] + 0.1, text(city_names[i], 8, :black, :bottom)) for i in 1:length(cities)])
    end

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
    
    # Determine Plot Limits from Data
    min_lat, max_lat = 90.0, -90.0
    min_lon, max_lon = 180.0, -180.0
    
    if !isempty(topology.gnb_locations)
        for p in topology.gnb_locations
            min_lat = min(min_lat, p.lat)
            max_lat = max(max_lat, p.lat)
            min_lon = min(min_lon, p.lon)
            max_lon = max(max_lon, p.lon)
        end
    end
    
    # Add buffer
    lat_buf = (max_lat - min_lat) * 0.05
    lon_buf = (max_lon - min_lon) * 0.05
    ylims_val = (min_lat - lat_buf, max_lat + lat_buf)
    xlims_val = (min_lon - lon_buf, max_lon + lon_buf)

    p = plot(
        title="6G-RUPA Network Graph: $operator_name",
        xlabel="Longitude",
        ylabel="Latitude",
        legend=false,
        size=(1200, 1000),
        aspect_ratio=:equal,
        ylims=ylims_val,
        xlims=xlims_val
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
