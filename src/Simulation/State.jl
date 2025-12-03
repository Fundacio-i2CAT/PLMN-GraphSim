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
        
        # Two-Tier: Add Default Route to Centralized UPF (PSA)
        if !isempty(topology.edge_upf_parent_map) && i <= length(topology.edge_upf_parent_map)
            parent_idx = topology.edge_upf_parent_map[i]
            # Default Route (0.0.0.0/0) -> Output Interface 2 (Uplink to PSA)
            entry = ForwardingEntry6GRUPA(UInt32(0), 0x00000000, Int32(2))
            push!(forwarding_tables[i], entry)
        end
    end
    return forwarding_tables
end

function init_centralized_state_6g_rupa(topology::NetworkTopology)
    num_centralized = length(topology.centralized_upf_locations)
    forwarding_tables = [Vector{ForwardingEntry6GRUPA}() for _ in 1:num_centralized]
    
    if num_centralized == 0
        return forwarding_tables
    end

    # Populate routes from Centralized UPF to Edge UPFs
    # Iterate through Edge UPFs and see who their parent is
    for (edge_idx, parent_idx) in enumerate(topology.edge_upf_parent_map)
        if parent_idx <= num_centralized
            # Add route to Edge UPF
            # Destination Prefix = Edge UPF ID (simplified)
            # In reality, this would be the subnet of the gNBs served by that Edge UPF
            # For now, let's assume we route based on Edge UPF ID
            entry = ForwardingEntry6GRUPA(UInt32(edge_idx), 0xFFFFFF00, Int32(1))
            push!(forwarding_tables[parent_idx], entry)
        end
    end
    
    return forwarding_tables
end

function init_global_state_for_simulation(topology::NetworkTopology, config::SimConfig)
    total_number_of_upfs = length(topology.upf_locations)
    forwarding_tables5g = init_state_5g(total_number_of_upfs)
    forwarding_tables_6grupa = init_state_6g_rupa(topology)
    centralized_forwarding_tables_6grupa = init_centralized_state_6g_rupa(topology)
    
    time = Float64[]
    total_5g_fwd_state_info_size_mb = Float64[]
    max_upf_5g_fwd_state_info_size_mb = Float64[]
    mean_upf_5g_fwd_state_info_size_mb = Float64[]
    median_upf_5g_fwd_state_info_size_mb = Float64[]
    total_6grupa_fwd_state_info_size_mb = Float64[]
    max_gupf_6grupa_fwd_state_info_size_mb = Float64[]
    mean_gupf_6grupa_fwd_state_info_size_mb = Float64[]
    median_gupf_6grupa_fwd_state_info_size_mb = Float64[]
    mean_entries_6grupa = Float64[]
    median_entries_6grupa = Float64[]
    history_per_upf_5g_fwd_state_info_size_mb = Vector{Float64}[]
    history_per_upf_entries_5g = Vector{Int}[]
    history_per_gupf_6grupa_fwd_state_info_size_mb = Vector{Float64}[]
    history_per_gupf_entries_6grupa = Vector{Int}[]
    return SimGlobalState(
        config,
        forwarding_tables5g,
        forwarding_tables_6grupa,
        centralized_forwarding_tables_6grupa,
        time,
        total_5g_fwd_state_info_size_mb,
        max_upf_5g_fwd_state_info_size_mb,
        mean_upf_5g_fwd_state_info_size_mb,
        median_upf_5g_fwd_state_info_size_mb,
        total_6grupa_fwd_state_info_size_mb,
        max_gupf_6grupa_fwd_state_info_size_mb,
        mean_gupf_6grupa_fwd_state_info_size_mb,
        median_gupf_6grupa_fwd_state_info_size_mb,
        mean_entries_6grupa,
        median_entries_6grupa,
        history_per_upf_5g_fwd_state_info_size_mb,
        history_per_upf_entries_5g,
        history_per_gupf_6grupa_fwd_state_info_size_mb,
        history_per_gupf_entries_6grupa
    )
end

function create_session_context(serving_upf_index::Int, topology::NetworkTopology)
    ul_teid = rand(UInt32)
    dl_teid = rand(UInt32)
    far_ul = FAR(0x01, rand(UInt32))
    far_dl = FAR(0x01, rand(UInt32))
    
    forwarding_state = ForwardingState5G(ul_teid, dl_teid, far_ul, far_dl)

    # Determine Anchor UPF (PSA)
    # If we are in two-tier mode, look up the parent.
    # If single-tier, the serving UPF is the anchor.
    anchor_upf_index = serving_upf_index
    if !isempty(topology.edge_upf_parent_map)
        # We assume 1-based indexing for UPFs
        if serving_upf_index <= length(topology.edge_upf_parent_map)
             anchor_upf_index = topology.edge_upf_parent_map[serving_upf_index]
        end
    end

    metadata = SessionSimMetadata(serving_upf_index, anchor_upf_index)
    return SessionContext5G(forwarding_state, metadata)
end
