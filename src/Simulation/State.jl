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

function init_global_state_for_simulation(topology::NetworkTopology, config::SimConfig)
    total_number_of_upfs = length(topology.upf_locations)
    forwarding_tables5g = init_state_5g(total_number_of_upfs)
    forwarding_tables_6grupa = init_state_6g_rupa(topology)
    time = Float64[]
    total_5g_mb = Float64[]
    max_upf_5g_mb = Float64[]
    mean_upf_5g_mb = Float64[]
    median_upf_5g_mb = Float64[]
    total_6grupa_mb = Float64[]
    max_gupf_6grupa_mb = Float64[]
    mean_gupf_6grupa_mb = Float64[]
    median_gupf_6grupa_mb = Float64[]
    mean_entries_6grupa = Float64[]
    median_entries_6grupa = Float64[]
    history_per_upf_5g_mb = Vector{Float64}[]
    history_per_upf_entries_5g = Vector{Int}[]
    history_per_gupf_6grupa_mb = Vector{Float64}[]
    history_per_gupf_entries_6grupa = Vector{Int}[]
    return SimGlobalState(
        config,
        forwarding_tables5g,
        forwarding_tables_6grupa,
        time,
        total_5g_mb,
        max_upf_5g_mb,
        mean_upf_5g_mb,
        median_upf_5g_mb,
        total_6grupa_mb,
        max_gupf_6grupa_mb,
        mean_gupf_6grupa_mb,
        median_gupf_6grupa_mb,
        mean_entries_6grupa,
        median_entries_6grupa,
        history_per_upf_5g_mb,
        history_per_upf_entries_5g,
        history_per_gupf_6grupa_mb,
        history_per_gupf_entries_6grupa
    )
end

function create_session_context()
    ul_teid = rand(UInt32)
    dl_teid = rand(UInt32)
    far_ul = FAR(0x01, rand(UInt32))
    far_dl = FAR(0x01, rand(UInt32))
    return SessionContext5G(ul_teid, dl_teid, far_ul, far_dl)
end
