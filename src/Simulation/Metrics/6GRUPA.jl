function collect_6grupa_metrics(sim_state::SimGlobalState)
    gupf_fwd_state_info_size_mb_6grupa = Float64[]
    gupf_entries_6grupa = Int[]
    for table in sim_state.forwarding_tables_6grupa
        table_fwd_state_info_size_mb = Base.summarysize(table) / (1024^2)
        gupf_fwd_state_info_size_mb = table_fwd_state_info_size_mb
        push!(gupf_fwd_state_info_size_mb_6grupa, gupf_fwd_state_info_size_mb)
        push!(gupf_entries_6grupa, length(table))
    end
    # Centralized UPF Metrics
    centralized_fwd_state_info_size_mb = Float64[]
    centralized_entries = Int[]
    for table in sim_state.centralized_forwarding_tables_6grupa
        table_size = Base.summarysize(table) / (1024^2)
        push!(centralized_fwd_state_info_size_mb, table_size)
        push!(centralized_entries, length(table))
    end

    return (
        per_gupf_fwd_state_info_size_mb=gupf_fwd_state_info_size_mb_6grupa,
        per_gupf_entries=gupf_entries_6grupa,
        per_centralized_gupf_fwd_state_info_size_mb=centralized_fwd_state_info_size_mb,
        per_centralized_gupf_entries=centralized_entries
    )
end
