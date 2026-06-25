using ConcurrentSim
using ResumableFunctions
using Distributions
using Random
using Graphs
using MetaGraphsNext
using ..Types
using ..AgentGeneration
using Logging

# Reference O(#gNB) nearest-gNB (kept for testing the spatial index against).
function find_serving_gnb_brute(topology::NetworkTopology, user_location::GeoPoint)
    min_dist = Inf
    best_idx = 0
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

# Fast nearest-gNB via a per-topology grid index (built once, cached). Returns the
# same result as the brute-force version; needed because mobility re-queries every
# agent every tick at national scale (tens of thousands of agents × 46k–113k gNBs).
function find_serving_gnb(topology::NetworkTopology, user_location::GeoPoint)
    return nearest_gnb(get_gnb_grid(topology.gnb_locations), topology.gnb_locations, user_location)
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

"""
    lifecycle_embb_mobile(env, user_id, sim_state, topology)

Mobile variant of `lifecycle_embb`. After attach, the agent periodically updates
its position according to `sim_state.config.mobility.model` and re-evaluates its
serving gNB. On a cell change a handover is triggered for both 5G and 6G-RUPA
state machines (event counters are bumped; 5G session contexts migrate UPFs).

The stationary `lifecycle_embb` is preserved unchanged so existing experiments
reproduce bit-for-bit when `mobility.enabled = false`.
"""
@resumable function lifecycle_embb_mobile(env, user_id, sim_state, topology::NetworkTopology)
    @yield @process await_user_offline(env, sim_state)
    agent_location = select_agent_location(topology)
    gnb_index = find_serving_gnb(topology, agent_location)
    gnb_index == 0 && return
    assigned_upf_index = connect_agent_to_gnb_and_upf(env, topology, user_id, agent_location, gnb_index)

    # Track this agent's session contexts so we can migrate them on handover.
    num_sessions = rand(sim_state.config.min_sessions:sim_state.config.max_sessions)
    agent_sessions = Vector{SessionContext5G}(undef, num_sessions)
    for i in 1:num_sessions
        ctx = create_session_context(assigned_upf_index, topology)
        push!(sim_state.upf_sessions_5g[assigned_upf_index], ctx)
        agent_sessions[i] = ctx
    end

    current_gnb = gnb_index
    current_upf = assigned_upf_index
    current_domain = assigned_upf_index  # Simple: domain ID = UPF index
    current_operator = 1                 # Single operator for now
    current_loc = agent_location
    update_dt = sim_state.config.mobility.update_interval
    model = sim_state.config.mobility.model

    # Initialize mobility state for this agent
    mobility_state = MobilityState(agent_location, 0.0, 0.0, 0.0, 0.0)

    while !is_simulation_time_over(env, sim_state)
        @yield timeout(env, update_dt)
        is_simulation_time_over(env, sim_state) && break
        current_loc = step_position(model, current_loc, mobility_state, update_dt)
        new_gnb = find_serving_gnb(topology, current_loc)
        if new_gnb == 0 || new_gnb == current_gnb
            continue
        end
        # Cell change detected -> handover.
        new_upf = topology.gnb_to_upf_map[new_gnb]
        new_domain = new_upf  # Domain = UPF index
        new_operator = 1      # Single operator

        # Update graph edges to reflect new attachment.
        if haskey(topology.graph, (:Agent, user_id), (:gNB, current_gnb))
            delete!(topology.graph, (:Agent, user_id), (:gNB, current_gnb))
        end
        d = haversine_distance(current_loc, topology.gnb_locations[new_gnb])
        add_edge!(topology.graph, (:Agent, user_id), (:gNB, new_gnb), d)

        # Drive both 5G (Xn/N2) and 6G-RUPA (intra/inter-domain) state machines
        # with the SAME pre-handover context, counting the event once. Must run
        # before mutating current_* so the 6G-RUPA path sees the real old domain.
        agent_sessions = dispatch_handover!(sim_state, topology, agent_sessions,
                                            current_gnb, new_gnb,
                                            current_upf, new_upf,
                                            current_domain, new_domain,
                                            current_operator, new_operator)
        current_upf = new_upf
        current_domain = new_domain
        current_gnb = new_gnb
        @debug "User $user_id handover: gNB $(current_gnb) -> $(new_gnb), UPF -> $(new_upf) at $(now(env))"
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
        if sim_state.config.mobility.enabled
            @yield @process lifecycle_embb_mobile(env, user_id, sim_state, topology)
        else
            @yield @process lifecycle_embb(env, user_id, sim_state, topology)
        end
    elseif user_type == mMTC
        @yield @process lifecycle_mmtc(env, user_id, sim_state, topology)
    end
end

