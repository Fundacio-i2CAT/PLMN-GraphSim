function collect_6grupa_metrics(sim_state::SimGlobalState)
    gupf_fwd_state_info_size_mb_6grupa = Float64[]
    gupf_entries_6grupa = Int[]
    for table in sim_state.forwarding_tables_6grupa
        table_fwd_state_info_size_mb = Base.summarysize(table) / (1024^2)
        gupf_fwd_state_info_size_mb = table_fwd_state_info_size_mb
        push!(gupf_fwd_state_info_size_mb_6grupa, gupf_fwd_state_info_size_mb)
        push!(gupf_entries_6grupa, length(table))
    end

    total_6grupa_fwd_state_info_size_mb = sum(gupf_fwd_state_info_size_mb_6grupa)
    max_gupf_6grupa_fwd_state_info_size_mb = isempty(gupf_fwd_state_info_size_mb_6grupa) ? 0.0 : maximum(gupf_fwd_state_info_size_mb_6grupa)
    mean_gupf_6grupa_fwd_state_info_size_mb = isempty(gupf_fwd_state_info_size_mb_6grupa) ? 0.0 : mean(gupf_fwd_state_info_size_mb_6grupa)
    median_gupf_6grupa_fwd_state_info_size_mb = isempty(gupf_fwd_state_info_size_mb_6grupa) ? 0.0 : median(gupf_fwd_state_info_size_mb_6grupa)

    mean_entries_6grupa = isempty(gupf_entries_6grupa) ? 0.0 : mean(gupf_entries_6grupa)
    median_entries_6grupa = isempty(gupf_entries_6grupa) ? 0.0 : median(gupf_entries_6grupa)

    return (
        total_fwd_state_info_size_mb=total_6grupa_fwd_state_info_size_mb, 
        max_fwd_state_info_size_mb=max_gupf_6grupa_fwd_state_info_size_mb, 
        mean_fwd_state_info_size_mb=mean_gupf_6grupa_fwd_state_info_size_mb, 
        median_fwd_state_info_size_mb=median_gupf_6grupa_fwd_state_info_size_mb, 
        mean_entries=mean_entries_6grupa, 
        median_entries=median_entries_6grupa,
        per_gupf_fwd_state_info_size_mb=gupf_fwd_state_info_size_mb_6grupa, 
        per_gupf_entries=gupf_entries_6grupa
    )
end

function calculate_6grupa_metrics(state::SimGlobalState)

    entries_6grupa = [length(t) for t in state.forwarding_tables_6grupa]
    mem_6grupa_allocated_mb = [Base.summarysize(t) / (1024^2) for t in state.forwarding_tables_6grupa]
    element_size_6grupa = sizeof(ForwardingEntry6GRUPA)
    mem_6grupa_raw_mb = [length(t) * element_size_6grupa / (1024^2) for t in state.forwarding_tables_6grupa]
    mem_per_entry_6grupa = [length(t) > 0 ? (Base.summarysize(t) / length(t)) : 0.0 for t in state.forwarding_tables_6grupa]
    
    return DataFrame(
        Entries_6GRUPA=entries_6grupa,
        Total_6GRUPA_FwdStateInfoSize_MB=mem_6grupa_allocated_mb,
        Raw_6GRUPA_FwdStateInfoSize_MB=mem_6grupa_raw_mb,
        Bytes_Per_Entry_6GRUPA=mem_per_entry_6grupa
    )
end
