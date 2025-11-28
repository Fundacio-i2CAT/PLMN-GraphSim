module Plotting

using Plots
using CSV
using DataFrames
using Clustering
using Random
using ..Types
using ..DataLoading
using ..AgentGeneration

export plot_operator_topology_with_cities

# --- Configuration ---
const NUM_AGENTS_TO_PLOT = 2000 

# --- Reference Cities (Provincial Capitals & Major Cities) ---
# Moved to Types.jl as REFERENCE_CITIES

# --- Plotting ---
function plot_operator_topology_with_cities(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String)
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
    println("Generating $NUM_AGENTS_TO_PLOT agents using population density...")
    agent_locs = generate_agent_locations(topology, NUM_AGENTS_TO_PLOT)
    
    agent_lons = [p.lon for p in agent_locs]
    agent_lats = [p.lat for p in agent_locs]

    # Extract gNB and UPF coords for plotting
    gnb_lons = [p.lon for p in topology.gnb_locations]
    gnb_lats = [p.lat for p in topology.gnb_locations]
    
    upf_lons = [p.lon for p in topology.upf_locations]
    upf_lats = [p.lat for p in topology.upf_locations]

    println("Plotting for $operator_name ($scenario_name)...")
    
    # Create Plot
    p = plot(
        title = "6G-RUPA Topology: $operator_name - $scenario_name",
        xlabel = "Longitude",
        ylabel = "Latitude",
        legend = :outertopright,
        size = (1200, 1000),
        aspect_ratio = :equal,
        ylims = (35, 44)
    )
    
    # 1. Plot gNBs (Base Stations) - Orange (Better visibility)
    scatter!(p, gnb_lons, gnb_lats, 
        label = "gNBs (Base Stations)", 
        markersize = 1.5, 
        markercolor = :orange, 
        markeralpha = 0.3,
        markerstrokewidth = 0
    )

    # 2. Plot Agents (Users) - Blue dots (High visibility)
    scatter!(p, agent_lons, agent_lats, 
        label = "Users (Agents)", 
        markersize = 1.5, 
        markercolor = :blue, 
        markeralpha = 0.6, 
        markerstrokewidth = 0
    )
    
    # 3. Plot UPFs (Core Network) - Large red squares
    scatter!(p, upf_lons, upf_lats, 
        label = "UPFs ($num_upfs Hubs)", 
        markersize = 7, 
        markercolor = :red, 
        markershape = :square,
        markerstrokewidth = 1
    )

    # Annotate UPFs with their ID
    annotate!(p, [(upf_lons[i], upf_lats[i], text(string(i), 8, :white, :center)) for i in 1:length(upf_lons)])

    # 3. Plot Reference Cities - Green Stars
    city_lons = [c[2].lon for c in REFERENCE_CITIES]
    city_lats = [c[2].lat for c in REFERENCE_CITIES]
    city_names = [c[1] for c in REFERENCE_CITIES]

    scatter!(p, city_lons, city_lats,
        label = "Major Cities",
        markersize = 5,
        markercolor = :green,
        markershape = :star5,
        markerstrokewidth = 1
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

end
