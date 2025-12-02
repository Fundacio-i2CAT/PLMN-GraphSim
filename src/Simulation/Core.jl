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

function is_simulation_time_over(env, sim_state)
    return now(env) >= sim_state.config.duration
end

function connect_agent_to_gnb_and_upf(env, topology::NetworkTopology, user_id::Int, agent_location::GeoPoint, gnb_index::Int)
    add_vertex!(topology.graph, (:Agent, user_id), agent_location)
    gnb_location = topology.gnb_locations[gnb_index]
    distance = haversine_distance(agent_location, gnb_location)
    add_edge!(topology.graph, (:Agent, user_id), (:gNB, gnb_index), distance)
    assigned_upf_index = topology.gnb_to_upf_map[gnb_index]
    @debug "User $user_id connected to gNB $gnb_index (UPF $assigned_upf_index) at time $(now(env))"
    return assigned_upf_index
end

function create_random_ue_connections(sim_state, assigned_upf_index::Int)
    num_sessions = rand(sim_state.config.min_sessions:sim_state.config.max_sessions)
    for _ in 1:num_sessions
        ctx = create_session_context()
        push!(sim_state.upf_sessions_5g[assigned_upf_index], ctx)
    end
    return num_sessions
end

function release_ue_connections(sim_state, assigned_upf_index::Int, num_sessions::Int)
    if !isempty(sim_state.upf_sessions_5g[assigned_upf_index])
        for _ in 1:num_sessions
            if !isempty(sim_state.upf_sessions_5g[assigned_upf_index])
                pop!(sim_state.upf_sessions_5g[assigned_upf_index])
            end
        end
    end
end

function disconnect_ue_from_gnb_and_upf(topology::NetworkTopology, user_id::Int, gnb_index::Int)
    delete!(topology.graph, (:Agent, user_id)) # Remove Agent from Graph
end

@resumable function await_user_offline(env, sim_state)
    offline_duration = rand(Exponential(sim_state.config.mean_offline_duration))
    @yield timeout(env, offline_duration)
end

@resumable function user_lifecycle(env, user_id, sim_state, topology::NetworkTopology)
    @yield await_user_offline(env, sim_state) # Random start delay to avoid thundering herd at t=0
    while true
        if is_simulation_time_over(env, sim_state)
            break
        end
        agent_location = select_agent_location(topology)
        gnb_index = find_serving_gnb(topology, agent_location)
        if gnb_index != 0
            assigned_upf_index = connect_agent_to_gnb_and_upf(env, topology, user_id, agent_location, gnb_index)
            num_sessions = create_random_ue_connections(sim_state, assigned_upf_index)
            session_duration = rand(Exponential(sim_state.config.mean_session_duration))
            @yield timeout(env, session_duration)
            release_ue_connections(sim_state, assigned_upf_index, num_sessions)
            @debug "User $user_id disconnected from gNB $gnb_index at time $(now(env))"
            disconnect_ue_from_gnb_and_upf(topology, user_id, gnb_index)
        end
        @yield await_user_offline(env, sim_state) # Offline / Inter-session wait
    end
end

