function collect_6grupa_metrics(sim_state::SimGlobalState)
    # Cost forwarding state the way the 5G metric does: entry count times the size
    # of one forwarding entry. Both architectures are then reported on a single
    # field-level convention, which is what makes the comparison like-for-like and
    # independent of how the runtime happens to lay out its arrays.
    #
    # Base.summarysize() was used here previously. It reports the ALLOCATED size of
    # a table, including per-array object overhead, so it inflated 6G-RUPA state by
    # 1.5-2.1x relative to the analytical convention applied to 5G, and it varied by
    # up to 30% with the k-means clustering, which changes how entries are spread
    # across tables. That made the comparison neither like-for-like nor stable
    # across runs. It is kept below under a separate name for transparency.
    element_size_mb = sizeof(ForwardingEntry6GRUPA) / (1024^2)

    gupf_entries_6grupa = Int[]
    gupf_allocated_mb = Float64[]
    for table in sim_state.forwarding_tables_6grupa
        push!(gupf_entries_6grupa, length(table))
        push!(gupf_allocated_mb, Base.summarysize(table) / (1024^2))
    end
    gupf_fwd_state_info_size_mb_6grupa = gupf_entries_6grupa .* element_size_mb

    # Centralized UPF Metrics, same convention.
    centralized_entries = Int[]
    centralized_allocated_mb = Float64[]
    for table in sim_state.centralized_forwarding_tables_6grupa
        push!(centralized_entries, length(table))
        push!(centralized_allocated_mb, Base.summarysize(table) / (1024^2))
    end
    centralized_fwd_state_info_size_mb = centralized_entries .* element_size_mb

    return (
        per_gupf_fwd_state_info_size_mb=gupf_fwd_state_info_size_mb_6grupa,
        per_gupf_entries=gupf_entries_6grupa,
        per_centralized_gupf_fwd_state_info_size_mb=centralized_fwd_state_info_size_mb,
        per_centralized_gupf_entries=centralized_entries,
        # Runtime-allocated sizes, reported for transparency; not used in the
        # architecture comparison, for the reasons given above.
        per_gupf_allocated_size_mb=gupf_allocated_mb,
        per_centralized_gupf_allocated_size_mb=centralized_allocated_mb
    )
end
