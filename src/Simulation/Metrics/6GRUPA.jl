function collect_6grupa_metrics(sim_state::SimGlobalState)
    upf_sizes_6grupa = Float64[]
    upf_entries_6grupa = Int[]

    for table in sim_state.forwarding_tables_6grupa
        table_size = Base.summarysize(table) / (1024^2)
        upf_total = table_size
        push!(upf_sizes_6grupa, upf_total)
        push!(upf_entries_6grupa, length(table))
    end

    total_6grupa_size = sum(upf_sizes_6grupa)
    max_upf_6grupa_size = isempty(upf_sizes_6grupa) ? 0.0 : maximum(upf_sizes_6grupa)
    mean_upf_6grupa_size = isempty(upf_sizes_6grupa) ? 0.0 : mean(upf_sizes_6grupa)
    median_upf_6grupa_size = isempty(upf_sizes_6grupa) ? 0.0 : median(upf_sizes_6grupa)

    mean_entries_6grupa = isempty(upf_entries_6grupa) ? 0.0 : mean(upf_entries_6grupa)
    median_entries_6grupa = isempty(upf_entries_6grupa) ? 0.0 : median(upf_entries_6grupa)

    return (
        total=total_6grupa_size, 
        max=max_upf_6grupa_size, 
        mean=mean_upf_6grupa_size, 
        median=median_upf_6grupa_size, 
        mean_entries=mean_entries_6grupa, 
        median_entries=median_entries_6grupa,
        per_upf_mb=upf_sizes_6grupa, 
        per_upf_entries=upf_entries_6grupa
    )
end

function calculate_6grupa_metrics(state::SimGlobalState)
    # Calculate 6G-RUPA metrics
    entries_6grupa = [length(t) for t in state.forwarding_tables_6grupa]
    
    # Allocated Memory 6G-RUPA
    mem_6grupa_allocated_mb = [Base.summarysize(t) / (1024^2) for t in state.forwarding_tables_6grupa]
    
    # Raw Memory 6G-RUPA
    # sizeof(ForwardingEntry6GRUPA) is 12 bytes
    element_size_6grupa = sizeof(ForwardingEntry6GRUPA)
    mem_6grupa_raw_mb = [length(t) * element_size_6grupa / (1024^2) for t in state.forwarding_tables_6grupa]

    mem_per_entry_6grupa = [length(t) > 0 ? (Base.summarysize(t) / length(t)) : 0.0 for t in state.forwarding_tables_6grupa]
    
    return DataFrame(
        Entries_6GRUPA=entries_6grupa,
        Total_Mem_6GRUPA_MB=mem_6grupa_allocated_mb,
        Raw_Mem_6GRUPA_MB=mem_6grupa_raw_mb,
        Bytes_Per_Entry_6GRUPA=mem_per_entry_6grupa
    )
end
