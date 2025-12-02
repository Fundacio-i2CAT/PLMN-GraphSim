using ConcurrentSim
using ResumableFunctions
using Distributions
using Random
using MetaGraphsNext
using ..Types
using ..AgentGeneration
using Logging

function find_serving_gnb(topology::NetworkTopology, user_location::GeoPoint)
    min_dist = Inf
    best_idx = 0
    # Optimization: We could use a spatial index, but for 40k points and 2k agents, 
    # brute force is ~80M ops. In Julia this is < 1s :D.
    for (i, gnb) in enumerate(topology.gnb_locations)
        # Euclidean distance approximation is fine for finding nearest neighbor locally
        d2 = (gnb.lat - user_location.lat)^2 + (gnb.lon - user_location.lon)^2
        if d2 < min_dist
            min_dist = d2
            best_idx = i
        end
    end
    return best_idx
end


@resumable function user_lifecycle(env, user_id, sim_state, topology::NetworkTopology)
    # Initial random start delay to avoid thundering herd at t=0
    initial_delay = rand(Exponential(sim_state.config.mean_offline_duration))
    @yield timeout(env, initial_delay)

    while true
        # Check if simulation time is over
        if now(env) >= sim_state.config.duration
            break
        end
        user_location = select_agent_location(topology) # User Placement (Population Distribution)
        gnb_idx = find_serving_gnb(topology, user_location) # Connect to Network -> Find nearest gNB
        if gnb_idx != 0
            # Add Agent to Graph and Connect to gNB
            add_vertex!(topology.graph, (:Agent, user_id), user_location)
            gnb_location = topology.gnb_locations[gnb_idx]
            distance_between_user_gnb_in_km = haversine_distance(user_location, gnb_location)
            add_edge!(topology.graph, (:Agent, user_id), (:gNB, gnb_idx), distance_between_user_gnb_in_km)
            
            assigned_upf_idx = topology.gnb_to_upf_map[gnb_idx]
            
            # Connect
            @debug "User $user_id connected to gNB $gnb_idx (UPF $assigned_upf_idx) at time $(now(env))"

            # Create 5G Forwarding State (Allocation)
            num_sessions = rand(sim_state.config.min_sessions:sim_state.config.max_sessions)
            for _ in 1:num_sessions
                ctx = create_session_context()
                push!(sim_state.upf_sessions_5g[assigned_upf_idx], ctx)
            end

            # Active duration
            session_duration = rand(Exponential(sim_state.config.mean_session_duration))
            @yield timeout(env, session_duration)

            # Disconnect
            if !isempty(sim_state.upf_sessions_5g[assigned_upf_idx])
                for _ in 1:num_sessions
                    if !isempty(sim_state.upf_sessions_5g[assigned_upf_idx])
                        pop!(sim_state.upf_sessions_5g[assigned_upf_idx])
                    end
                end
            end
            @debug "User $user_id disconnected from gNB $gnb_idx at time $(now(env))"

            # Remove Agent from Graph (Cleanup)
            delete!(topology.graph, (:Agent, user_id))
        end

        # Offline / Inter-session wait
        offline_duration = rand(Exponential(sim_state.config.mean_offline_duration))
        @yield timeout(env, offline_duration)
    end
end
