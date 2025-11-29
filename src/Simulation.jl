module Simulation

using Agents
using ConcurrentSim
using ResumableFunctions
using Distributions
using Random
using DataFrames
using CSV
using Dates
using Graphs
using MetaGraphsNext
using ..Types
using ..DataLoading
using ..AgentGeneration

export run_operator_simulation, init_global_state, create_session_context

# # Number of PDU Sessions per User. Tipycal eMBB UE: Internet + IMS for VoNR)
const MIN_SESSIONS = 1
const MAX_SESSIONS = 2

function init_state_5g(num_upfs::Int)
    # 5G State Initialization
    # Initialize empty session lists for each UPF.
    # Sessions are created dynamically as users connect.
    return [Vector{SessionContext5G}() for _ in 1:num_upfs]
end

function init_state_6g_rupa(topology::NetworkTopology)
    num_upfs = length(topology.upf_locations)
    # 6G-RUPA State Initialization
    # Each UPF needs a forwarding entry for each gNB it serves.
    # We populate this based on the topology graph edges (One entry per connected gNB).
    forwarding_tables = [Vector{ForwardingEntry6GRUPA}() for _ in 1:num_upfs]

    for i in 1:num_upfs
        upf_label = (:UPF, i)
        # Check if UPF exists in graph (it should)
        if haskey(topology.graph, upf_label)
            u_code = code_for(topology.graph, upf_label)
            # Iterate over all neighbors (connected edges)
            for v_code in neighbors(topology.graph, u_code)
                v_label = label_for(topology.graph, v_code)
                # If the neighbor is a gNB, add a forwarding entry
                if v_label[1] == :gNB
                    gnb_id = v_label[2]
                    # Create a route for this gNB
                    # Destination Prefix = gNB ID (simplified representation)
                    entry = ForwardingEntry6GRUPA(UInt32(gnb_id), 0xFFFFFF00, Int32(1))
                    push!(forwarding_tables[i], entry)
                end
            end
        end
    end
    return forwarding_tables
end

function init_global_state(topology::NetworkTopology)
    num_upfs = length(topology.upf_locations)
    upf_sessions = init_state_5g(num_upfs)
    forwarding_tables_6g = init_state_6g_rupa(topology)
    qos = [QoSConfig6GRUPA(Int8(i), Int8(i), 0.5, 1e-6) for i in 1:16]
    return SimGlobalState(
        upf_sessions,
        forwarding_tables_6g,
        qos,
        Float64[], # time
        Float64[], # total 5g mb
        Float64[], # max upf 5g mb
        Float64[], # total 6g mb
        Float64[]  # max upf 6g mb
    )
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


@resumable function user_lifecycle(env, user_id, sim_state, topology::NetworkTopology)
    user_loc = select_agent_location(topology) # User Placement (Population Distribution)
    gnb_idx = find_serving_gnb(topology, user_loc) # Connect to Network -> Find nearest gNB
    if gnb_idx == 0
        return # Should never happen, but safety check
    end

    # Add Agent to Graph and Connect to gNB
    # We use a lock or ensure thread safety if running in parallel threads, 
    # but ConcurrentSim is single-threaded (coroutine based), so this is safe.
    add_vertex!(topology.graph, (:Agent, user_id), user_loc)

    gnb_loc = topology.gnb_locations[gnb_idx]
    dist_km = haversine_distance(user_loc, gnb_loc)
    add_edge!(topology.graph, (:Agent, user_id), (:gNB, gnb_idx), dist_km)

    assigned_upf_idx = topology.gnb_to_upf_map[gnb_idx]
    arrival_delay = rand(Exponential(5.0)) # Spread out arrivals
    @yield timeout(env, arrival_delay)

    # Connect
    # TODO In a full simulation, we would calculate latency based on distance: user -> gnb -> upf

    # Create 5G Forwarding State (Allocation)
    # Simulate multiple sessions per user (e.g. Internet, VoLTE, IoT device...)
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

    # Remove Agent from Graph (Cleanup)
    # MetaGraphsNext uses delete! for removing vertices by label
    delete!(topology.graph, (:Agent, user_id))
end

@resumable function monitor_metrics(env, sim_state::SimGlobalState)
    while true
        current_time = now(env)
        # Calculate 5G State
        # By now, total Network State AND Max State on a single UPF (Bottleneck)
        total_5g_size = 0.0
        max_upf_size = 0.0

        for sessions in sim_state.upf_sessions_5g
            # Calculate size of this UPF's session list
            # XXX: summarysize is accurate but can be slow. 
            # For simulation speed, we can estimate: count * sizeof(SessionContext5G)
            # But let's stick to summarysize for accuracy unless it's too slow.
            upf_size = Base.summarysize(sessions) / (1024^2)
            total_5g_size += upf_size
            if upf_size > max_upf_size
                max_upf_size = upf_size
            end
        end

        # Calculate 6G-RUPA State (Static per GUPF, but we track it for consistency)
        total_6g_size = 0.0
        max_upf_6g_size = 0.0

        # QoS Profiles are shared/global usually, or per UPF. Let's assume per UPF copy.
        qos_size = Base.summarysize(sim_state.qos_profiles_6g) / (1024^2)

        for table in sim_state.forwarding_tables_6g
            # Size of the forwarding table for this UPF
            table_size = Base.summarysize(table) / (1024^2)

            # Total state for this UPF = Table + QoS
            upf_total = table_size + qos_size

            total_6g_size += upf_total
            if upf_total > max_upf_6g_size
                max_upf_6g_size = upf_total
            end
        end

        push!(sim_state.history_time, current_time)
        push!(sim_state.history_total_5g_mb, total_5g_size)
        push!(sim_state.history_max_upf_5g_mb, max_upf_size)
        push!(sim_state.history_total_6g_mb, total_6g_size)
        push!(sim_state.history_max_upf_6g_mb, max_upf_6g_size)

        @yield timeout(env, 1.0) # Sample every 1.0 time unit
    end
end

function save_simulation_results(operator_name::String, scenario_name::String, state::SimGlobalState)
    df = DataFrame(
        Time=state.history_time,
        Total_5G_MB=state.history_total_5g_mb,
        Max_UPF_5G_MB=state.history_max_upf_5g_mb,
        Total_6G_MB=state.history_total_6g_mb,
        Max_UPF_6G_MB=state.history_max_upf_6g_mb
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

function save_raw_upf_data(operator_name::String, scenario_name::String, state::SimGlobalState, scale_factor::Int)
    # 5G Data (Scaled to Real World)
    upf_ids = 1:length(state.upf_sessions_5g)
    # Calculate 5G metrics
    entries_5g = [length(s) * scale_factor for s in state.upf_sessions_5g]
    mem_5g_mb = [Base.summarysize(s) / (1024^2) * scale_factor for s in state.upf_sessions_5g]
    # Average bytes per entry (including vector overhead distributed)
    mem_per_entry_5g = [length(s) > 0 ? (Base.summarysize(s) / length(s)) : 0.0 for s in state.upf_sessions_5g]
    # Calculate 6G metrics
    entries_6g = [length(t) for t in state.forwarding_tables_6g]
    mem_6g_mb = [Base.summarysize(t) / (1024^2) for t in state.forwarding_tables_6g]
    mem_per_entry_6g = [length(t) > 0 ? (Base.summarysize(t) / length(t)) : 0.0 for t in state.forwarding_tables_6g]
    df = DataFrame(
        UPF_ID=upf_ids,
        Entries_5G=entries_5g,
        Total_Mem_5G_MB=mem_5g_mb,
        Bytes_Per_Entry_5G=mem_per_entry_5g,
        Entries_6G=entries_6g,
        Total_Mem_6G_MB=mem_6g_mb,
        Bytes_Per_Entry_6G=mem_per_entry_6g
    )
    results_dir = joinpath(@__DIR__, "../results")
    if !isdir(results_dir)
        mkdir(results_dir)
    end
    filename = "raw_upf_state_$(operator_name)_$(scenario_name).csv"
    CSV.write(joinpath(results_dir, filename), df)
    println("Raw UPF state data saved to $filename")
end

function print_forwarding_tables(state::SimGlobalState, scale_factor::Int)
    println("\n--- Detailed Forwarding State Dump ---")
    println("\n[5G Architecture] Per-UPF Session Contexts (Dynamic State):")
    for (i, sessions) in enumerate(state.upf_sessions_5g)
        mem_mb = Base.summarysize(sessions) / (1024^2)
        num_entries = length(sessions)
        # We agreggate calculations just by scaling the number of sessions.
        real_entries = num_entries * scale_factor
        real_mem_mb = mem_mb * scale_factor
        println("  UPF #$i:")
        println("    Forwarding Entries: $real_entries (Active PDU Sessions)")
        println("    Memory Usage:       $(round(real_mem_mb, digits=4)) MB")
    end

    println("\n[6G-RUPA Architecture] GUPF Forwarding Tables (Static/Topological State):")
    for (i, table) in enumerate(state.forwarding_tables_6g)
        mem_mb = Base.summarysize(table) / (1024^2)
        num_entries = length(table)
        println("  GUPF #$i:")
        println("    Forwarding Entries: $num_entries")
        println("    Memory Usage:       $(round(mem_mb, digits=6)) MB")
    end
end

function run_operator_simulation(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String; scale_factor::Int=1)
    println("\n==================================================")
    println("RUNNING SIMULATION: $operator_name ($scenario_name)")
    println("==================================================")

    # Simplification: 1 Agent = 1 UE
    # We use a smaller population for testing, or the full effective population if scale_factor=1
    # But to avoid crashing with 40M agents, let's assume the user passes a reasonable scale_factor
    # that results in a manageable number of agents for the simulation engine.
    # However, for the "1 UE = 1 Agent" logic requested, we treat the simulated agents as the total universe.

    num_agents = ceil(Int, EFFECTIVE_POPULATION / scale_factor)
    println("Configuration:")
    println("  Scale Factor: 1 Agent represents $scale_factor real people (Simulation uses $num_agents agents)")
    println("  Assumption: 1 Active UE per Agent")

    csv_path = joinpath(@__DIR__, "../data/214.csv")

    if !isfile(csv_path)
        error("Data file not found at $csv_path")
    end

    # 1. Setup Network
    topology = load_and_deploy_network(csv_path, operator_id, num_upfs)

    println("Network Deployed:")
    println("  gNBs: $(length(topology.gnb_locations))")
    println("  UPFs: $(length(topology.upf_locations))")
    println("  Simulated Users: $num_agents")

    # 2. Setup Simulation
    sim = ConcurrentSim.Simulation()
    global_state = init_global_state(topology)

    # Start Monitor Process
    @process monitor_metrics(sim, global_state)

    # Spawn Agents
    for i in 1:num_agents
        @process user_lifecycle(sim, i, global_state, topology)
    end

    # Run
    println("Starting Simulation...")
    run(sim, 100.0) # Run for 100 time units

    println("Simulation Complete.")
    println("Final Total 5G State: $(last(global_state.history_total_5g_mb)) MB")
    println("Final Max UPF 5G State: $(last(global_state.history_max_upf_5g_mb)) MB")
    println("Final Total 6G-RUPA State: $(last(global_state.history_total_6g_mb)) MB")
    println("Final Max GUPF 6G-RUPA State: $(last(global_state.history_max_upf_6g_mb)) MB")

    # Calculate Scaled Impact
    # 5G State is per-UE, so we scale it up to represent the full population.
    real_world_total_5g_mb = last(global_state.history_total_5g_mb) * scale_factor
    real_world_max_upf_5g_mb = last(global_state.history_max_upf_5g_mb) * scale_factor

    # 6G State is per-gNB (Topology based). Since we use the REAL topology (all gNBs),
    # we do NOT scale this. It is already at real-world scale.
    real_world_total_6g_mb = last(global_state.history_total_6g_mb)
    real_world_max_upf_6g_mb = last(global_state.history_max_upf_6g_mb)

    println("\n--- Real World Extrapolation ($operator_name - $scenario_name) ---")
    println("Estimated Total 5G Network State: $(real_world_total_5g_mb / 1024) GB")
    println("Estimated Max UPF Load (Bottleneck): $(real_world_max_upf_5g_mb / 1024) GB")
    println("Estimated Total 6G-RUPA State: $(real_world_total_6g_mb) MB")
    println("Estimated Max GUPF Load (Bottleneck): $(real_world_max_upf_6g_mb) MB")
    print_forwarding_tables(global_state, scale_factor)
    save_simulation_results(operator_name, scenario_name, global_state)
    save_raw_upf_data(operator_name, scenario_name, global_state, scale_factor)
end

end
