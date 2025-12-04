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

function create_random_ue_connections(sim_state, assigned_upf_index::Int, topology::NetworkTopology)
    num_sessions = rand(sim_state.config.min_sessions:sim_state.config.max_sessions)
    for _ in 1:num_sessions
        ctx = create_session_context(assigned_upf_index, topology)
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

@resumable function lifecycle_embb(env, user_id, sim_state, topology::NetworkTopology)
    # Random start delay to simulate users joining the network over time (Ramp-up)
    @yield @process await_user_offline(env, sim_state)
    # eMBB Logic: User attaches and stays attached ("Always On")
    # We select a location once. (Mobility could be added later, but for State Analysis, static attachment is sufficient)
    agent_location = select_agent_location(topology)
    gnb_index = find_serving_gnb(topology, agent_location)
    if gnb_index != 0
        # Attach UE to Network, connect to gNB and UPF
        assigned_upf_index = connect_agent_to_gnb_and_upf(env, topology, user_id, agent_location, gnb_index)
        # Establish PDU Sessions, Forwarding State gets created
        num_sessions = create_random_ue_connections(sim_state, assigned_upf_index, topology)
        @debug "User $user_id (eMBB) attached (Always-On) to gNB $gnb_index at time $(now(env))"
        # Maintain Session until Simulation End
        # In eMBB, the PDU session remains active even if traffic is bursty.
        remaining_time = sim_state.config.duration - now(env)
        if remaining_time > 0
            @yield timeout(env, remaining_time)
        end
        # Simulation ends, implicit cleanup.
    end
end

@resumable function lifecycle_mmtc(env, user_id, sim_state, topology::NetworkTopology)
    # TODO Placeholder for mMTC logic
    # mMTC devices might wake up, send data, and go back to sleep (idle mode), releasing resources?
    # Or they might stay registered but release PDU sessions?
    # For now, we just wait.
    @yield timeout(env, sim_state.config.duration)
end

@resumable function user_lifecycle(env, user_id, sim_state, topology::NetworkTopology, user_type::UserType)
    if user_type == eMBB
        @yield @process lifecycle_embb(env, user_id, sim_state, topology)
    elseif user_type == mMTC
        @yield @process lifecycle_mmtc(env, user_id, sim_state, topology)
    end
end

