function collect_5g_metrics(sim_state::SimGlobalState, scale_factor::Int)
    upf_fwd_state_info_size_mb_5g = Float64[]
    for sessions in sim_state.upf_sessions_5g
        # Calculate memory usage of this UPF's session list
        # Scale the number of sessions
        num_sessions = length(sessions) * scale_factor
        upf_fwd_state_info_size_mb = (num_sessions * sizeof(ForwardingState5G)) / (1024^2)
        push!(upf_fwd_state_info_size_mb_5g, upf_fwd_state_info_size_mb)
    end

    total_5g_fwd_state_info_size_mb = sum(upf_fwd_state_info_size_mb_5g)
    max_upf_fwd_state_info_size_mb = isempty(upf_fwd_state_info_size_mb_5g) ? 0.0 : maximum(upf_fwd_state_info_size_mb_5g)
    mean_upf_fwd_state_info_size_mb = isempty(upf_fwd_state_info_size_mb_5g) ? 0.0 : mean(upf_fwd_state_info_size_mb_5g)
    median_upf_fwd_state_info_size_mb = isempty(upf_fwd_state_info_size_mb_5g) ? 0.0 : median(upf_fwd_state_info_size_mb_5g)
    
    upf_entries_5g = [length(s) * scale_factor for s in sim_state.upf_sessions_5g]

    return (
        total_fwd_state_info_size_mb=total_5g_fwd_state_info_size_mb, 
        max_fwd_state_info_size_mb=max_upf_fwd_state_info_size_mb, 
        mean_fwd_state_info_size_mb=mean_upf_fwd_state_info_size_mb, 
        median_fwd_state_info_size_mb=median_upf_fwd_state_info_size_mb, 
        per_upf_fwd_state_info_size_mb=upf_fwd_state_info_size_mb_5g, 
        per_upf_entries=upf_entries_5g
    )
end

function calculate_5g_metrics(state::SimGlobalState, scale_factor::Int)
    upf_ids = 1:length(state.upf_sessions_5g)
    
    # Calculate 5G metrics
    entries_5g = [length(s) * scale_factor for s in state.upf_sessions_5g]
    
    # Raw Memory (Used - theoretical minimum for the data stored)
    # sizeof(ForwardingState5G) is 24 bytes
    element_size_5g = sizeof(ForwardingState5G)
    mem_5g_raw_mb = [length(s) * element_size_5g / (1024^2) * scale_factor for s in state.upf_sessions_5g]

    # We use the same value for "Total" as we are now ignoring allocation overhead
    mem_5g_allocated_mb = mem_5g_raw_mb

    # Average bytes per entry (Fixed size)
    mem_per_entry_5g = fill(Float64(element_size_5g), length(upf_ids))
    
    return DataFrame(
        UPF_ID=upf_ids,
        Entries_5G=entries_5g,
        Total_5G_FwdStateInfoSize_MB=mem_5g_allocated_mb, # Now same as Raw
        Raw_5G_FwdStateInfoSize_MB=mem_5g_raw_mb,         # Theoretical minimum (Julia struct)
        Bytes_Per_Entry_5G=mem_per_entry_5g
    )
end
