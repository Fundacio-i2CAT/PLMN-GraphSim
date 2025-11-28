using Plots
using CSV
using DataFrames
using Clustering
using Random
using Printf

# --- Configuration ---
const NUM_UPFS = 52 # One per province
const NUM_AGENTS_TO_PLOT = 5000 

# --- Reference Cities (Provincial Capitals & Major Cities) ---
# Name, Lat, Lon
const CITIES = [
    ("Madrid", 40.4168, -3.7038),
    ("Barcelona", 41.3851, 2.1734),
    ("Valencia", 39.4699, -0.3763),
    ("Seville", 37.3891, -5.9845),
    ("Zaragoza", 41.6488, -0.8891),
    ("Málaga", 36.7212, -4.4217),
    ("Murcia", 37.9922, -1.1307),
    ("Palma", 39.5696, 2.6502),
    ("Bilbao", 43.2630, -2.9350),
    ("Alicante", 38.3452, -0.4810),
    ("Córdoba", 37.8882, -4.7794),
    ("Valladolid", 41.6523, -4.7245),
    ("Vigo", 42.2406, -8.7207),
    ("Gijón", 43.5322, -5.6611),
    ("A Coruña", 43.3623, -8.4115),
    ("Vitoria", 42.8467, -2.6716),
    ("Granada", 37.1773, -3.5986),
    ("Oviedo", 43.3619, -5.8494),
    ("Pamplona", 42.8125, -1.6458),
    ("Almería", 36.8340, -2.4637),
    ("San Sebastián", 43.3183, -1.9812),
    ("Burgos", 42.3439, -3.6969),
    ("Santander", 43.4623, -3.8099),
    ("Castellón", 39.9864, -0.0513),
    ("Albacete", 38.9943, -1.8585),
    ("Logroño", 42.4623, -2.4449),
    ("Badajoz", 38.8794, -6.9706),
    ("Salamanca", 40.9701, -5.6635),
    ("Huelva", 37.2614, -6.9447),
    ("Lleida", 41.6176, 0.6200),
    ("Tarragona", 41.1189, 1.2445),
    ("León", 42.5987, -5.5671),
    ("Cádiz", 36.5271, -6.2886),
    ("Jaén", 37.7749, -3.7902),
    ("Ourense", 42.3358, -7.8639),
    ("Lugo", 43.0125, -7.5558),
    ("Girona", 41.9794, 2.8214),
    ("Cáceres", 39.4753, -6.3723),
    ("Santiago", 42.8782, -8.5448),
    ("Toledo", 39.8628, -4.0273),
    ("Guadalajara", 40.6328, -3.1602),
    ("Cuenca", 40.0704, -2.1374),
    ("Ciudad Real", 38.9848, -3.9274),
    ("Zamora", 41.5063, -5.7446),
    ("Palencia", 42.0095, -4.5286),
    ("Segovia", 40.9429, -4.1088),
    ("Soria", 41.7640, -2.4688),
    ("Teruel", 40.3456, -1.1065),
    ("Huesca", 42.1361, -0.4087),
    ("Ávila", 40.6565, -4.6813)
]

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
    k = min(NUM_UPFS, nrow(df))
    println("Clustering into $k UPF regions...")
    R = kmeans(gnb_coords, k; maxiter=100)
    
    upf_lons = R.centers[1, :]
    upf_lats = R.centers[2, :]
    
    return df, upf_lons, upf_lats
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
function plot_operator_topology_with_cities(operator_name::String, operator_id::Int)
    csv_path = joinpath(@__DIR__, "../data/214.csv")
    if !isfile(csv_path)
        error("Data file not found at $csv_path")
    end
    
    # 1. Get Data
    df_gnb, upf_lons, upf_lats = load_and_cluster(csv_path, operator_id)
    
    if nrow(df_gnb) == 0
        println("No data for $operator_name. Skipping.")
        return
    end

    # 2. Generate Agents
    agent_lons, agent_lats = generate_agents(df_gnb, NUM_AGENTS_TO_PLOT)

    println("Plotting for $operator_name...")
    
    # Create Plot
    p = plot(
        title = "6G-RUPA Topology: $operator_name (Spain)",
        xlabel = "Longitude",
        ylabel = "Latitude",
        legend = :outertopright,
        size = (1200, 1000),
        aspect_ratio = :equal
    )
    
    # 1. Plot gNBs (Base Stations) - Orange (Better visibility)
    scatter!(p, df_gnb.lon, df_gnb.lat, 
        label = "gNBs (Base Stations)", 
        markersize = 1.5, 
        markercolor = :orange, 
        markeralpha = 0.3,
        markerstrokewidth = 0
    )

    # 2. Plot Agents (Users) - Black dots
    scatter!(p, agent_lons, agent_lats, 
        label = "Users (Agents)", 
        markersize = 1.5, 
        markercolor = :black, 
        markeralpha = 0.4,
        markerstrokewidth = 0
    )
    
    # 3. Plot UPFs (Core Network) - Large red squares
    scatter!(p, upf_lons, upf_lats, 
        label = "UPFs (Provincial Hubs)", 
        markersize = 7, 
        markercolor = :red, 
        markershape = :square,
        markerstrokewidth = 1
    )

    # 3. Plot Reference Cities - Green Stars
    city_lons = [c[3] for c in CITIES]
    city_lats = [c[2] for c in CITIES]
    city_names = [c[1] for c in CITIES]

    scatter!(p, city_lons, city_lats,
        label = "Major Cities",
        markersize = 5,
        markercolor = :green,
        markershape = :star5,
        markerstrokewidth = 1
    )

    # Annotate Cities
    annotate!(p, [(city_lons[i], city_lats[i] + 0.1, text(city_names[i], 8, :black, :bottom)) for i in 1:length(CITIES)])
    
    # Save
    output_dir = joinpath(@__DIR__, "../images")
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    output_filename = "topology_map_cities_$(lowercase(operator_name)).png"
    output_path = joinpath(output_dir, output_filename)
    savefig(p, output_path)
    println("Plot saved to $output_path")
end

function plot_all_operators()
    plot_operator_topology_with_cities("Vodafone", 1)
    plot_operator_topology_with_cities("Orange", 3)
    plot_operator_topology_with_cities("Movistar", 7)
end

if abspath(PROGRAM_FILE) == @__FILE__
    plot_all_operators()
end