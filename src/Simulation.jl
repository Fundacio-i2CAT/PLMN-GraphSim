module Simulation

using Agents
using ConcurrentSim
using ResumableFunctions
using Distributions
using Random
using DataFrames
using CSV
using Dates
using ..Types
using ..DataLoading
using ..AgentGeneration

export run_operator_simulation, init_global_state, create_session_context

# --- Configuration ---
const SPAIN_POPULATION = 47_000_000
# Demographics: ~14.5% under 15 (no phone), 96% of >15 have phone, source INE 2023
const RATIO_UNDER_15 = 0.145
const PHONE_ADOPTION_OVER_15 = 0.96
const EFFECTIVE_POPULATION = SPAIN_POPULATION * (1 - RATIO_UNDER_15) * PHONE_ADOPTION_OVER_15

const SIMULATION_SCALE = 1_00 # 1 Agent = 100 people
const NUM_AGENTS = ceil(Int, EFFECTIVE_POPULATION / SIMULATION_SCALE)

# Number of PDU Sessions per User
# Standard Smartphone: 1 (Internet) or 2 (Internet + IMS for VoNR)
const MIN_SESSIONS = 1
const MAX_SESSIONS = 2

function init_global_state(num_upfs::Int)
    # Initialize empty session lists for each UPF
    upf_sessions = [Vector{SessionContext5G}() for _ in 1:num_upfs]

    fwd = [ForwardingEntry6GRUPA(0x0A000000, 0xFFFFFF00, 1), ForwardingEntry6GRUPA(0x0A000100, 0xFFFFFF00, 2)]
    qos = [QoSConfig6GRUPA(Int8(i), Int8(i), 0.5, 1e-6) for i in 1:16]

    return SimGlobalState(upf_sessions, fwd, qos, Float64[], Float64[], Float64[], Float64[])
end

function create_session_context()
    return SessionContext5G(rand(UInt32), rand(UInt32), FAR(0x01, rand(UInt32)), FAR(0x01, rand(UInt32)))
end

function find_serving_gnb(topology::NetworkTopology, user_loc::GeoPoint)
    min_dist = Inf
    best_idx = 0
    
    # Optimization: We could use a spatial index, but for 40k points and 2k agents, 
    # brute force is ~80M ops. In Julia this is < 1s.
    for (i, gnb) in enumerate(topology.gnb_locations)
        # Euclidean distance approximation is fine for finding nearest neighbor locally
        d2 = (gnb.lat - user_loc.lat)^2 + (gnb.lon - user_loc.lon)^2
        if d2 < min_dist
            min_dist = d2
            best_idx = i
        end
    end
    return best_idx
end

# --- DES Processes ---

@resumable function user_lifecycle(env, user_id, sim_state, topology::NetworkTopology)
    # 1. User Placement (Population Distribution)
    # Use unified AgentGeneration logic
    user_loc = select_agent_location(topology)

    # 2. Connect to Network (Find nearest gNB)
    gnb_idx = find_serving_gnb(topology, user_loc)
    
    if gnb_idx == 0
        # Should not happen given the logic, but safety check
        return
    end

    assigned_upf_idx = topology.gnb_to_upf_map[gnb_idx]

    # Arrival
    arrival_delay = rand(Exponential(5.0)) # Spread out arrivals
    @yield timeout(env, arrival_delay)

    # Connect
    # In a full simulation, we would calculate latency based on distance:
    # user -> gnb -> upf

    # Create 5G State (Allocation)
    # Simulate multiple sessions per user (e.g. Internet, VoLTE, IoT device)
    num_sessions = rand(MIN_SESSIONS:MAX_SESSIONS)

    for _ in 1:num_sessions
        ctx = create_session_context()
        push!(sim_state.upf_sessions_5g[assigned_upf_idx], ctx)
    end

    # Active duration
    duration = rand(Exponential(20.0))
    @yield timeout(env, duration)

    # Disconnect
    # Remove the same number of sessions we added from the specific UPF
    if !isempty(sim_state.upf_sessions_5g[assigned_upf_idx])
        for _ in 1:num_sessions
            if !isempty(sim_state.upf_sessions_5g[assigned_upf_idx])
                pop!(sim_state.upf_sessions_5g[assigned_upf_idx])
            end
        end
    end
end

@resumable function monitor_metrics(env, sim_state::SimGlobalState)
    while true
        current_time = now(env)

        # Calculate 5G State
        # We want: Total Network State AND Max State on a single UPF (Bottleneck)
        total_5g_size = 0.0
        max_upf_size = 0.0

        for sessions in sim_state.upf_sessions_5g
            # Calculate size of this UPF's session list
            # Note: summarysize is accurate but can be slow. 
            # For simulation speed, we can estimate: count * sizeof(SessionContext5G)
            # But let's stick to summarysize for accuracy unless it's too slow.
            upf_size = Base.summarysize(sessions) / (1024^2)
            total_5g_size += upf_size
            if upf_size > max_upf_size
                max_upf_size = upf_size
            end
        end

        # Calculate 6G-RUPA State (Constant per GUPF)
        size_6g = (Base.summarysize(sim_state.forwarding_table_6g) + Base.summarysize(sim_state.qos_profiles_6g)) / (1024^2)

        push!(sim_state.history_time, current_time)
        push!(sim_state.history_total_5g_mb, total_5g_size)
        push!(sim_state.history_max_upf_5g_mb, max_upf_size)
        push!(sim_state.history_6g_mb, size_6g)

        @yield timeout(env, 1.0) # Sample every 1.0 time unit
    end
end

function save_simulation_results(operator_name::String, scenario_name::String, state::SimGlobalState)
    df = DataFrame(
        Time=state.history_time,
        Total_5G_MB=state.history_total_5g_mb,
        Max_UPF_5G_MB=state.history_max_upf_5g_mb,
        Size6GRUPA_MB=state.history_6g_mb
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

function print_forwarding_tables(state::SimGlobalState)
    println("\n--- Detailed Forwarding State Dump ---")
    
    println("\n[5G Architecture] Per-UPF Session Contexts (Dynamic State):")
    for (i, sessions) in enumerate(state.upf_sessions_5g)
        mem_mb = Base.summarysize(sessions) / (1024^2)
        num_entries = length(sessions)
        println("  UPF #$i:")
        println("    Forwarding Entries: $num_entries (Active PDU Sessions)")
        println("    Memory Usage:       $(round(mem_mb, digits=4)) MB")
        if !isempty(sessions)
            # Print first session as sample
            s = sessions[1]
            println("    Sample Session:     UL_TEID=$(s.ul_teid), DL_TEID=$(s.dl_teid), DestIP=$(s.ul_far.destination_ip)")
        end
    end

    println("\n[6G-RUPA Architecture] GUPF Forwarding Table (Static/Topological State):")
    println("  (Note: This table is identical for all GUPFs in this simulation scenario)")
    
    mem_6g = (Base.summarysize(state.forwarding_table_6g) + Base.summarysize(state.qos_profiles_6g)) / (1024^2)
    println("  Total Memory per GUPF: $(round(mem_6g, digits=6)) MB")

    println("  Forwarding Table ($(length(state.forwarding_table_6g)) entries):")
    for (i, entry) in enumerate(state.forwarding_table_6g)
        println("    Entry #$i: Prefix=$(entry.dest_prefix), Mask=$(entry.mask), OutIf=$(entry.output_interface)")
    end
    println("  QoS Profiles ($(length(state.qos_profiles_6g)) entries):")
    for (i, qos) in enumerate(state.qos_profiles_6g)
        println("    Profile #$i: QFI=$(qos.qfi), Prio=$(qos.priority), Delay=$(qos.packet_delay_budget)ms")
    end
end

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
    sim = ConcurrentSim.Simulation()
    global_state = init_global_state(length(topology.upf_locations))

    # Start Monitor Process
    @process monitor_metrics(sim, global_state)

    # Spawn Agents
    for i in 1:NUM_AGENTS
        @process user_lifecycle(sim, i, global_state, topology)
    end

    # Run
    println("Starting Simulation...")
    run(sim, 100.0) # Run for 100 time units

    println("Simulation Complete.")
    println("Final Total 5G State: $(last(global_state.history_total_5g_mb)) MB")
    println("Final Max UPF 5G State: $(last(global_state.history_max_upf_5g_mb)) MB")
    println("Final 6G-RUPA GUPF State: $(last(global_state.history_6g_mb)) MB")

    # Calculate Scaled Impact
    real_world_total_5g_mb = last(global_state.history_total_5g_mb) * SIMULATION_SCALE
    real_world_max_upf_5g_mb = last(global_state.history_max_upf_5g_mb) * SIMULATION_SCALE

    println("\n--- Real World Extrapolation ($operator_name - $scenario_name) ---")
    println("Estimated Total 5G Network State: $(real_world_total_5g_mb / 1024) GB")
    println("Estimated Max UPF Load (Bottleneck): $(real_world_max_upf_5g_mb / 1024) GB")
    println("Estimated 6G-RUPA State (Constant per Node): $(last(global_state.history_6g_mb)) MB")

    print_forwarding_tables(global_state)

    save_simulation_results(operator_name, scenario_name, global_state)
end

end
