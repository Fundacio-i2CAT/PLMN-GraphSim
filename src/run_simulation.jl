using Agents
using ConcurrentSim
using ResumableFunctions
using Graphs
using MetaGraphsNext
using Distributions
using Random
using Printf
using CSV
using DataFrames
using Clustering
using Geodesy

# --- Configuration ---
const SPAIN_POPULATION = 47_000_000
const SIMULATION_SCALE = 1_000 # 1 Agent = 1,000 people
const NUM_AGENTS = ceil(Int, SPAIN_POPULATION / SIMULATION_SCALE)
const NUM_UPFS = 50 # Number of UPFs (One per Province + Ceuta/Melilla - Canary Islands)

# --- Shared Structures ---
# (Reusing the lightweight structures for memory tracking)
struct FAR
    action::UInt8
    destination_ip::UInt32
end

struct SessionContext5G
    ul_teid::UInt32
    dl_teid::UInt32
    ul_far::FAR
    dl_far::FAR
end

struct ForwardingEntry6G
    dest_prefix::UInt32
    mask::UInt32
    output_interface::Int32
end

struct QoSConfig6G
    qfi::Int8
    priority::Int8
    packet_delay_budget::Float64
    packet_error_rate::Float64
end

# --- Simulation State ---
mutable struct SimGlobalState
    active_sessions_5g::Vector{SessionContext5G}
    forwarding_table_6g::Vector{ForwardingEntry6G}
    qos_profiles_6g::Vector{QoSConfig6G}
    
    history_time::Vector{Float64}
    history_size_5g_mb::Vector{Float64}
    history_size_6g_mb::Vector{Float64}
end

function init_global_state()
    fwd = [ForwardingEntry6G(0x0A000000, 0xFFFFFF00, 1), ForwardingEntry6G(0x0A000100, 0xFFFFFF00, 2)]
    qos = [QoSConfig6G(Int8(i), Int8(i), 0.5, 1e-6) for i in 1:16]
    return SimGlobalState(Vector{SessionContext5G}(), fwd, qos, Float64[], Float64[], Float64[])
end

function create_session_context()
    return SessionContext5G(rand(UInt32), rand(UInt32), FAR(0x01, rand(UInt32)), FAR(0x01, rand(UInt32)))
end

# --- Network Topology ---

struct GeoPoint
    lat::Float64
    lon::Float64
end

struct NetworkTopology
    gnb_locations::Vector{GeoPoint}
    upf_locations::Vector{GeoPoint}
    gnb_to_upf_map::Vector{Int} # Index of UPF for each gNB
    
    # Population Distribution
    province_bins::Dict{String, Vector{Int}}
    province_names::Vector{String}
    province_probs::Vector{Float64}
end

# --- Province Centroids (Approximate) ---
const PROVINCE_CENTROIDS = Dict(
    "Albacete" => GeoPoint(38.9943, -1.8585),
    "Alicante/Alacant" => GeoPoint(38.3452, -0.4810),
    "Almería" => GeoPoint(36.8340, -2.4637),
    "Araba/Álava" => GeoPoint(42.8467, -2.6716),
    "Asturias" => GeoPoint(43.3614, -5.8593),
    "Ávila" => GeoPoint(40.6565, -4.7002),
    "Badajoz" => GeoPoint(38.8794, -6.9706),
    "Balears, Illes" => GeoPoint(39.6953, 3.0176),
    "Barcelona" => GeoPoint(41.3851, 2.1734),
    "Bizkaia" => GeoPoint(43.2630, -2.9350),
    "Burgos" => GeoPoint(42.3439, -3.6969),
    "Cáceres" => GeoPoint(39.4753, -6.3723),
    "Cádiz" => GeoPoint(36.5271, -6.2886),
    "Cantabria" => GeoPoint(43.1828, -3.9878),
    "Castellón/Castelló" => GeoPoint(39.9864, -0.0513),
    "Ciudad Real" => GeoPoint(38.9848, -3.9274),
    "Córdoba" => GeoPoint(37.8882, -4.7794),
    "Coruña, A" => GeoPoint(43.3623, -8.4115),
    "Cuenca" => GeoPoint(40.0704, -2.1374),
    "Gipuzkoa" => GeoPoint(43.3183, -1.9812),
    "Girona" => GeoPoint(41.9794, 2.8214),
    "Granada" => GeoPoint(37.1773, -3.5986),
    "Guadalajara" => GeoPoint(40.6328, -3.1632),
    "Huelva" => GeoPoint(37.2614, -6.9447),
    "Huesca" => GeoPoint(42.1361, -0.4087),
    "Jaén" => GeoPoint(37.7796, -3.7849),
    "León" => GeoPoint(42.5987, -5.5671),
    "Lleida" => GeoPoint(41.6176, 0.6200),
    "Lugo" => GeoPoint(43.0097, -7.5568),
    "Madrid" => GeoPoint(40.4168, -3.7038),
    "Málaga" => GeoPoint(36.7213, -4.4214),
    "Murcia" => GeoPoint(37.9922, -1.1307),
    "Navarra" => GeoPoint(42.8125, -1.6458),
    "Ourense" => GeoPoint(42.3358, -7.8639),
    "Palencia" => GeoPoint(42.0095, -4.5286),
    "Pontevedra" => GeoPoint(42.4299, -8.6446),
    "Rioja, La" => GeoPoint(42.2871, -2.5396),
    "Salamanca" => GeoPoint(40.9701, -5.6635),
    "Segovia" => GeoPoint(40.9429, -4.1088),
    "Sevilla" => GeoPoint(37.3891, -5.9845),
    "Soria" => GeoPoint(41.7666, -2.4735),
    "Tarragona" => GeoPoint(41.1189, 1.2445),
    "Teruel" => GeoPoint(40.3456, -1.1065),
    "Toledo" => GeoPoint(39.8628, -4.0273),
    "Valencia/València" => GeoPoint(39.4699, -0.3763),
    "Valladolid" => GeoPoint(41.6523, -4.7245),
    "Zamora" => GeoPoint(41.5063, -5.7446),
    "Zaragoza" => GeoPoint(41.6488, -0.8891),
    "Ceuta" => GeoPoint(35.8894, -5.3213),
    "Melilla" => GeoPoint(35.2923, -2.9381)
)

function load_and_deploy_network(csv_path::String, pop_csv_path::String, operator_net_id::Int, num_upfs::Int)
    println("Loading gNB data from $csv_path for Operator ID: $operator_net_id...")
    # Columns: radio, mcc, net, area, cell, unit, lon, lat, ...
    df = CSV.read(csv_path, DataFrame; header=[:radio, :mcc, :net, :area, :cell, :unit, :lon, :lat, :range, :samples, :changeable, :created, :updated, :avg_signal])
    
    # Filter valid coordinates for Spain (approx bounding box)
    # Mainland Spain + Ceuta/Melilla (Excluding Canary Islands)
    # Lat: 35 to 45, Lon: -19 to 5
    filter!(row -> 35.0 <= row.lat <= 45.0 && -19.0 <= row.lon <= 5.0, df)

    # Filter for Specific Operator
    filter!(row -> row.net == operator_net_id, df)
    
    gnb_coords = Matrix{Float64}(undef, 2, nrow(df))
    gnb_coords[1, :] = df.lon
    gnb_coords[2, :] = df.lat
    
    println("  Found $(nrow(df)) valid gNBs for Operator $operator_net_id.")
    
    # --- Load Population Data ---
    println("Loading Population Data from $pop_csv_path...")
    pop_df = CSV.read(pop_csv_path, DataFrame)
    filter!(row -> row.Province != "Total Nacional", pop_df)
    # Filter out Canary Islands
    filter!(row -> row.Province != "Palmas, Las" && row.Province != "Santa Cruz de Tenerife", pop_df)
    
    total_pop = sum(pop_df.Population)
    pop_df.prob = pop_df.Population ./ total_pop
    
    province_names = String.(pop_df.Province)
    province_probs = Float64.(pop_df.prob)
    
    # --- Bin gNBs to Provinces ---
    println("Classifying gNBs into provinces...")
    province_bins = Dict{String, Vector{Int}}()
    for name in province_names
        province_bins[name] = Int[]
    end
    
    gnb_points = [GeoPoint(r.lat, r.lon) for r in eachrow(df)]
    
    for (i, gnb) in enumerate(gnb_points)
        min_dist = Inf
        best_prov = ""
        
        for (name, centroid) in PROVINCE_CENTROIDS
            d = (gnb.lat - centroid.lat)^2 + (gnb.lon - centroid.lon)^2
            if d < min_dist
                min_dist = d
                best_prov = name
            end
        end
        
        if haskey(province_bins, best_prov)
            push!(province_bins[best_prov], i)
        end
    end
    
    # Remove empty bins from probability list to avoid selecting empty provinces
    valid_indices = [i for i in 1:length(province_names) if !isempty(province_bins[province_names[i]])]
    final_names = province_names[valid_indices]
    final_probs = province_probs[valid_indices]
    # Renormalize probabilities
    if !isempty(final_probs)
        final_probs = final_probs ./ sum(final_probs)
    end
    
    println("  Provinces with coverage: $(length(final_names)) / $(length(province_names))")

    # --- Deploy UPFs using K-Means Clustering ---
    actual_k = min(num_upfs, nrow(df))
    println("Deploying $actual_k UPFs using K-Means clustering...")
    
    R = kmeans(gnb_coords, actual_k; maxiter=100)
    
    upf_locs = Vector{GeoPoint}()
    for i in 1:actual_k
        # Centroids are [lon, lat]
        push!(upf_locs, GeoPoint(R.centers[2, i], R.centers[1, i]))
    end
    
    # Map each gNB to nearest UPF (assignments from kmeans)
    gnb_to_upf = R.assignments
    
    return NetworkTopology(gnb_points, upf_locs, gnb_to_upf, province_bins, final_names, final_probs)
end

# --- DES Processes ---

@resumable function user_lifecycle(env, user_id, sim_state, topology::NetworkTopology)
    # 1. User Placement (Population Distribution)
    # Pick a Province based on Population Probability
    r = rand()
    cumulative = 0.0
    selected_province = ""
    
    # Weighted Random Selection
    for (i, prob) in enumerate(topology.province_probs)
        cumulative += prob
        if r <= cumulative
            selected_province = topology.province_names[i]
            break
        end
    end
    
    # Fallback (floating point errors)
    if selected_province == "" && !isempty(topology.province_names)
        selected_province = topology.province_names[end]
    end
    
    # Pick a random gNB within that province
    gnb_idx = 1
    if selected_province != "" && haskey(topology.province_bins, selected_province)
        candidates = topology.province_bins[selected_province]
        if !isempty(candidates)
            gnb_idx = rand(candidates)
        else
             # Fallback to global random if bin is empty (shouldn't happen due to filtering)
             gnb_idx = rand(1:length(topology.gnb_locations))
        end
    else
        gnb_idx = rand(1:length(topology.gnb_locations))
    end

    assigned_upf_idx = topology.gnb_to_upf_map[gnb_idx]
    
    # Arrival
    arrival_delay = rand(Exponential(5.0)) # Spread out arrivals
    @yield timeout(env, arrival_delay)
    
    # Connect
    # In a full simulation, we would calculate latency based on distance:
    # user -> gnb -> upf
    
    # Create 5G State (Allocation)
    # 1 Session per user (scaled)
    ctx = create_session_context()
    push!(sim_state.active_sessions_5g, ctx)
    
    record_metrics(env, sim_state)
    
    # Active duration
    duration = rand(Exponential(20.0))
    @yield timeout(env, duration)
    
    # Disconnect
    if !isempty(sim_state.active_sessions_5g)
        pop!(sim_state.active_sessions_5g)
    end
    record_metrics(env, sim_state)
end

function record_metrics(env, sim_state)
    current_time = now(env)
    size_5g = Base.summarysize(sim_state.active_sessions_5g) / (1024^2)
    size_6g = (Base.summarysize(sim_state.forwarding_table_6g) + Base.summarysize(sim_state.qos_profiles_6g)) / (1024^2)
    
    push!(sim_state.history_time, current_time)
    push!(sim_state.history_size_5g_mb, size_5g)
    push!(sim_state.history_size_6g_mb, size_6g)
end

function save_simulation_results(operator_name::String, scenario_name::String, state::SimGlobalState)
    df = DataFrame(
        Time = state.history_time,
        Size5G_MB = state.history_size_5g_mb,
        Size6G_MB = state.history_size_6g_mb
    )
    
    # Create results directory if it doesn't exist
    results_dir = joinpath(@__DIR__, "../results")
    if !isdir(results_dir)
        mkdir(results_dir)
    end
    
    filename = "simulation_results_$(operator_name)_$(scenario_name).csv"
    CSV.write(joinpath(results_dir, filename), df)
    println("Results saved to $filename")
end

# --- Main ---

function run_operator_simulation(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String)
    println("\n==================================================")
    println("RUNNING SIMULATION: $operator_name ($scenario_name)")
    println("==================================================")

    csv_path = joinpath(@__DIR__, "../data/214.csv")
    pop_csv_path = joinpath(@__DIR__, "../data/population_ine.csv")
    
    if !isfile(csv_path)
        error("Data file not found at $csv_path")
    end
    if !isfile(pop_csv_path)
        error("Population data file not found at $pop_csv_path. Run fetch_ine_data.jl first.")
    end
    
    # 1. Setup Network
    topology = load_and_deploy_network(csv_path, pop_csv_path, operator_id, num_upfs)
    
    println("Network Deployed:")
    println("  gNBs: $(length(topology.gnb_locations))")
    println("  UPFs: $(length(topology.upf_locations))")
    println("  Simulated Users: $NUM_AGENTS (Stress Test)")
    
    # 2. Setup Simulation
    sim = Simulation()
    global_state = init_global_state()
    
    # Spawn Agents
    for i in 1:NUM_AGENTS
        @process user_lifecycle(sim, i, global_state, topology)
    end
    
    # Run
    println("Starting Simulation...")
    run(sim, 100.0) # Run for 100 time units
    
    println("Simulation Complete.")
    println("Final 5G UPF State Size: $(last(global_state.history_size_5g_mb)) MB")
    println("Final 6G-RUPA GUPF State Size: $(last(global_state.history_size_6g_mb)) MB")
    
    # Calculate Scaled Impact
    real_world_5g_mb = last(global_state.history_size_5g_mb) * SIMULATION_SCALE
    println("\n--- Real World Extrapolation ($operator_name - $scenario_name) ---")
    println("Estimated 5G State for 47M Users: $(real_world_5g_mb / 1024) GB")
    println("Estimated 6G State (Constant): $(last(global_state.history_size_6g_mb)) MB")

    save_simulation_results(operator_name, scenario_name, global_state)
end

function run_all_scenarios()
    # Scenario 1: Centralized (Legacy 4G-like) - 3 UPFs (e.g., Madrid, Barcelona, Seville)
    println("\n>>> SCENARIO 1: CENTRALIZED (Legacy 4G-like) - 3 UPFs <<<")
    run_operator_simulation("Vodafone", 1, 3, "Centralized")
    run_operator_simulation("Orange", 3, 3, "Centralized")
    run_operator_simulation("Movistar", 7, 3, "Centralized")

    # Scenario 2: Distributed (5G Edge) - 52 UPFs (Provincial)
    println("\n>>> SCENARIO 2: DISTRIBUTED (5G Edge) - 52 UPFs <<<")
    run_operator_simulation("Vodafone", 1, 52, "Distributed")
    run_operator_simulation("Orange", 3, 52, "Distributed")
    run_operator_simulation("Movistar", 7, 52, "Distributed")
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_all_scenarios()
end
