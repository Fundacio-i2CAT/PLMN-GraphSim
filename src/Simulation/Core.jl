using ConcurrentSim
using ResumableFunctions
using Distributions
using Random
using MetaGraphsNext
using ..Types
using ..AgentGeneration

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
