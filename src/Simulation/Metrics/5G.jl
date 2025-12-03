function collect_5g_metrics(sim_state::SimGlobalState, topology::NetworkTopology, scale_factor::Int)
    num_edge = length(topology.upf_locations)
    num_psa = length(topology.centralized_upf_locations)
    total_upfs = num_edge + num_psa
    all_upf_entries = zeros(Int, total_upfs)
    # Iterate over Edge UPFs (which hold the sessions)
    # sim_state.upf_sessions_5g has size total_upfs, but only 1:num_edge are populated with sessions
    for edge_idx in 1:num_edge
        sessions = sim_state.upf_sessions_5g[edge_idx]
        # Tier 1: Edge UPF Load
        num_sessions = length(sessions) * scale_factor
        all_upf_entries[edge_idx] = num_sessions  
        # Tier 2: PSA UPF Load (derived from sessions)
        if num_psa > 0
            for session in sessions
                anchor_idx = session.metadata.anchor_upf_index
                # anchor_idx is relative to the list of PSAs (1..num_psa)
                if anchor_idx > 0 && anchor_idx <= num_psa
                    # Map to the combined vector index: num_edge + anchor_idx
                    all_upf_entries[num_edge + anchor_idx] += scale_factor
                end
            end
        end
    end
    element_size_mb = sizeof(ForwardingState5G) / (1024^2)
    all_upf_fwd_state_info_size_mb = all_upf_entries .* element_size_mb

    return (
        per_upf_fwd_state_info_size_mb=all_upf_fwd_state_info_size_mb, 
        per_upf_entries=all_upf_entries
    )
end