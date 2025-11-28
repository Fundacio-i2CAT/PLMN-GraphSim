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
const SIMULATION_SCALE = 10_000 # 1 Agent = 10,000 people
const NUM_AGENTS = ceil(Int, SPAIN_POPULATION / SIMULATION_SCALE)
const NUM_UPFS = 52 # Number of UPFs (One per Province + Ceuta/Melilla)

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
end

function load_and_deploy_network(csv_path::String, operator_net_id::Int, num_upfs::Int)
    println("Loading gNB data from $csv_path for Operator ID: $operator_net_id...")
    # Columns: radio, mcc, net, area, cell, unit, lon, lat, ...
    df = CSV.read(csv_path, DataFrame; header=[:radio, :mcc, :net, :area, :cell, :unit, :lon, :lat, :range, :samples, :changeable, :created, :updated, :avg_signal])
    
    # Filter valid coordinates for Spain (approx bounding box)
    # Lat: 36 to 44, Lon: -9 to 4
    filter!(row -> 35.0 <= row.lat <= 45.0 && -10.0 <= row.lon <= 5.0, df)

    # Filter for Specific Operator
    filter!(row -> row.net == operator_net_id, df)
    
    gnb_coords = Matrix{Float64}(undef, 2, nrow(df))
    gnb_coords[1, :] = df.lon
    gnb_coords[2, :] = df.lat
    
    println("  Found $(nrow(df)) valid gNBs for Operator $operator_net_id.")
    
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
    
    gnb_points = [GeoPoint(r.lat, r.lon) for r in eachrow(df)]
    
    return NetworkTopology(gnb_points, upf_locs, gnb_to_upf)
end

# --- DES Processes ---

@resumable function user_lifecycle(env, user_id, sim_state, topology::NetworkTopology)
    # 1. User Placement (Population Distribution)
    # Pick a random gNB to spawn near (Density-based distribution)
    gnb_idx = rand(1:length(topology.gnb_locations))
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

# --- Main ---

function run_operator_simulation(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String)
    println("\n==================================================")
    println("RUNNING SIMULATION: $operator_name ($scenario_name)")
    println("==================================================")

    csv_path = joinpath(@__DIR__, "../data/214.csv")
    if !isfile(csv_path)
        error("Data file not found at $csv_path")
    end
    
    # 1. Setup Network
    topology = load_and_deploy_network(csv_path, operator_id, num_upfs)
    
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
