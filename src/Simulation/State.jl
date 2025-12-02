using Agents
using Graphs
using MetaGraphsNext
using ..Types

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

function init_global_state(topology::NetworkTopology, config::SimConfig)
    num_upfs = length(topology.upf_locations)
    upf_sessions = init_state_5g(num_upfs)
    forwarding_tables_6g = init_state_6g_rupa(topology)
    qos = [QoSConfig6GRUPA(Int8(i), Int8(i), 0.5, 1e-6) for i in 1:16]
    return SimGlobalState(
        config,
        upf_sessions,
        forwarding_tables_6g,
        qos,
        Float64[], # time
        Float64[], # total 5g mb
        Float64[], # max upf 5g mb
        Float64[], # mean upf 5g mb
        Float64[], # median upf 5g mb
        Float64[], # total 6g mb
        Float64[], # max upf 6g mb
        Float64[], # mean upf 6g mb
        Float64[], # median upf 6g mb
        Float64[], # mean entries 6g
        Float64[]  # median entries 6g
    )
end

function create_session_context()
    return SessionContext5G(rand(UInt32), rand(UInt32), FAR(0x01, rand(UInt32)), FAR(0x01, rand(UInt32)))
end
