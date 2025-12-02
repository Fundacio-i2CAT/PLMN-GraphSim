function collect_5g_metrics(sim_state::SimGlobalState)
    upf_sizes_5g = Float64[]
    for sessions in sim_state.upf_sessions_5g
        # Calculate size of this UPF's session list
        upf_size = Base.summarysize(sessions) / (1024^2)
        push!(upf_sizes_5g, upf_size)
    end

    total_5g_size = sum(upf_sizes_5g)
    max_upf_size = isempty(upf_sizes_5g) ? 0.0 : maximum(upf_sizes_5g)
    mean_upf_size = isempty(upf_sizes_5g) ? 0.0 : mean(upf_sizes_5g)
    median_upf_size = isempty(upf_sizes_5g) ? 0.0 : median(upf_sizes_5g)
    
    upf_entries_5g = [length(s) for s in sim_state.upf_sessions_5g]

    return (
        total=total_5g_size, 
        max=max_upf_size, 
        mean=mean_upf_size, 
        median=median_upf_size, 
        per_upf_mb=upf_sizes_5g, 
        per_upf_entries=upf_entries_5g
    )
end

function calculate_5g_metrics(state::SimGlobalState, scale_factor::Int)
    upf_ids = 1:length(state.upf_sessions_5g)
    
    # Calculate 5G metrics
    entries_5g = [length(s) * scale_factor for s in state.upf_sessions_5g]
    
    # Allocated Memory (Capacity - includes unused reserved space from dynamic growth)
    mem_5g_allocated_mb = [Base.summarysize(s) / (1024^2) * scale_factor for s in state.upf_sessions_5g]
    
    # Raw Memory (Used - theoretical minimum for the data stored)
    # sizeof(SessionContext5G) is 24 bytes
    element_size_5g = sizeof(SessionContext5G)
    mem_5g_raw_mb = [length(s) * element_size_5g / (1024^2) * scale_factor for s in state.upf_sessions_5g]

    # Average bytes per entry (Allocated)
    mem_per_entry_5g = [length(s) > 0 ? (Base.summarysize(s) / length(s)) : 0.0 for s in state.upf_sessions_5g]
    
    return DataFrame(
        UPF_ID=upf_ids,
        Entries_5G=entries_5g,
        Total_Mem_5G_MB=mem_5g_allocated_mb, # Allocated/Capacity
        Raw_Mem_5G_MB=mem_5g_raw_mb,         # Theoretical minimum (Julia struct)
        Bytes_Per_Entry_5G=mem_per_entry_5g
    )
end
