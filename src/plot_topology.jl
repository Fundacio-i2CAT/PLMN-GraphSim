using Plots
using CSV
using DataFrames
using Clustering
using Random
using Printf

# --- Configuration ---
const NUM_UPFS = 52 # One per province
const NUM_AGENTS_TO_PLOT = 5000 # Plot a subset of agents to avoid clutter

# --- Helper Structures ---
struct GeoPoint
    lat::Float64
    lon::Float64
end

# --- Load Data & Cluster ---
function load_and_cluster(csv_path::String, operator_id::Int)
    println("Loading gNB data from $csv_path for Operator $operator_id...")
    df = CSV.read(csv_path, DataFrame; header=[:radio, :mcc, :net, :area, :cell, :unit, :lon, :lat, :range, :samples, :changeable, :created, :updated, :avg_signal])
    
    # Filter valid coordinates for Spain
    filter!(row -> 35.0 <= row.lat <= 45.0 && -10.0 <= row.lon <= 5.0, df)

    # Filter for Specific Operator
    filter!(row -> row.net == operator_id, df)
    
    gnb_coords = Matrix{Float64}(undef, 2, nrow(df))
    gnb_coords[1, :] = df.lon
    gnb_coords[2, :] = df.lat
    
    println("  Found $(nrow(df)) valid gNBs.")
    
    # K-Means for UPFs
    # Ensure we don't ask for more clusters than points
    k = min(NUM_UPFS, nrow(df))
    println("Clustering into $k UPF regions...")
    R = kmeans(gnb_coords, k; maxiter=100)
    
    upf_lons = R.centers[1, :]
    upf_lats = R.centers[2, :]
    
    return df, upf_lons, upf_lats, R.assignments
end

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
function plot_operator_topology(operator_name::String, operator_id::Int)
    csv_path = joinpath(@__DIR__, "../data/214.csv")
    if !isfile(csv_path)
        error("Data file not found at $csv_path")
    end
    
    # 1. Get Data
    df_gnb, upf_lons, upf_lats, assignments = load_and_cluster(csv_path, operator_id)
    
    if nrow(df_gnb) == 0
        println("No data for $operator_name. Skipping.")
        return
    end

    agent_lons, agent_lats = generate_agents(df_gnb, NUM_AGENTS_TO_PLOT)
    
    println("Plotting for $operator_name...")
    
    # Create Plot
    p = plot(
        title = "6G-RUPA Topology: $operator_name (Spain)",
        xlabel = "Longitude",
        ylabel = "Latitude",
        legend = :outertopright,
        size = (1000, 800),
        aspect_ratio = :equal
    )
    
    # 1. Plot gNBs (Base Stations) - Small grey dots
    scatter!(p, df_gnb.lon, df_gnb.lat, 
        label = "gNBs (Base Stations)", 
        markersize = 1, 
        markercolor = :grey, 
        markeralpha = 0.3,
        markerstrokewidth = 0
    )
    
    # 2. Plot Agents (Users) - Small blue dots
    scatter!(p, agent_lons, agent_lats, 
        label = "Users (Agents)", 
        markersize = 2, 
        markercolor = :blue, 
        markeralpha = 0.5,
        markerstrokewidth = 0
    )
    
    # 3. Plot UPFs (Core Network) - Large red squares
    scatter!(p, upf_lons, upf_lats, 
        label = "UPFs (Provincial Hubs)", 
        markersize = 6, 
        markercolor = :red, 
        markershape = :square,
        markerstrokewidth = 1
    )
    
    # Save
    output_filename = "topology_map_$(lowercase(operator_name)).png"
    output_path = joinpath(@__DIR__, "../$output_filename")
    savefig(p, output_path)
    println("Plot saved to $output_path")
end

function plot_all_operators()
    plot_operator_topology("Vodafone", 1)
    plot_operator_topology("Orange", 3)
    plot_operator_topology("Movistar", 7)
end

if abspath(PROGRAM_FILE) == @__FILE__
    plot_all_operators()
end
