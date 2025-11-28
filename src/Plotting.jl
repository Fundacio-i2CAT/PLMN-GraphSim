module Plotting

using Plots
using CSV
using DataFrames
using Clustering
using Random
using ..Types
using ..DataLoading

export plot_operator_topology_with_cities

# --- Configuration ---
const NUM_AGENTS_TO_PLOT = 2000 

# --- Reference Cities (Provincial Capitals & Major Cities) ---
# Moved to Types.jl as REFERENCE_CITIES

# --- Generate Agents ---
function generate_agents(df_gnb, num_agents)
    println("Generating $num_agents random agents based on gNB density...")
    agent_lons = Float64[]
    agent_lats = Float64[]
    
    num_gnbs = nrow(df_gnb)
    if num_gnbs == 0
        return agent_lons, agent_lats
    end
    
    for _ in 1:num_agents
        # Pick a random gNB
        idx = rand(1:num_gnbs)
        gnb = df_gnb[idx, :]
        
        # Add small jitter to simulate user being *near* the tower, not *on* it
        # 0.01 degrees is roughly 1km
        jitter_lon = (rand() - 0.5) * 0.02 
        jitter_lat = (rand() - 0.5) * 0.02
        
        push!(agent_lons, gnb.lon + jitter_lon)
        push!(agent_lats, gnb.lat + jitter_lat)
    end
    
    return agent_lons, agent_lats
end

# --- Plotting ---
function plot_operator_topology_with_cities(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String)
    csv_path = joinpath(@__DIR__, "../data/214.csv")
    if !isfile(csv_path)
        error("Data file not found at $csv_path")
    end
    
    # 1. Get Data
    df_gnb, upf_lons, upf_lats = load_and_cluster(csv_path, operator_id, num_upfs)
    
    if nrow(df_gnb) == 0
        println("No data for $operator_name. Skipping.")
        return
    end

    # 2. Generate Agents
    agent_lons, agent_lats = generate_agents(df_gnb, NUM_AGENTS_TO_PLOT)

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
    scatter!(p, df_gnb.lon, df_gnb.lat, 
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
