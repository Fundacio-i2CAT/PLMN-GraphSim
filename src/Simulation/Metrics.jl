using ConcurrentSim
using ResumableFunctions
using Dates
using DataFrames
using Statistics
using ..Types

@resumable function monitor_metrics(env, sim_state::SimGlobalState)
    while true
        current_time = now(env)
        
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

        # --- 6G-RUPA Metrics ---
        upf_sizes_6g = Float64[]
        upf_entries_6g = Int[]
        qos_size = Base.summarysize(sim_state.qos_profiles_6g) / (1024^2)

        for table in sim_state.forwarding_tables_6g
            table_size = Base.summarysize(table) / (1024^2)
            upf_total = table_size + qos_size
            push!(upf_sizes_6g, upf_total)
            push!(upf_entries_6g, length(table))
        end

        total_6g_size = sum(upf_sizes_6g)
        max_upf_6g_size = isempty(upf_sizes_6g) ? 0.0 : maximum(upf_sizes_6g)
        mean_upf_6g_size = isempty(upf_sizes_6g) ? 0.0 : mean(upf_sizes_6g)
        median_upf_6g_size = isempty(upf_sizes_6g) ? 0.0 : median(upf_sizes_6g)

        mean_entries_6g = isempty(upf_entries_6g) ? 0.0 : mean(upf_entries_6g)
        median_entries_6g = isempty(upf_entries_6g) ? 0.0 : median(upf_entries_6g)

        # --- Record History ---
        push!(sim_state.history_time, current_time)
        
        push!(sim_state.history_total_5g_mb, total_5g_size)
        push!(sim_state.history_max_upf_5g_mb, max_upf_size)
        push!(sim_state.history_mean_upf_5g_mb, mean_upf_size)
        push!(sim_state.history_median_upf_5g_mb, median_upf_size)

        push!(sim_state.history_total_6g_mb, total_6g_size)
        push!(sim_state.history_max_upf_6g_mb, max_upf_6g_size)
        push!(sim_state.history_mean_upf_6g_mb, mean_upf_6g_size)
        push!(sim_state.history_median_upf_6g_mb, median_upf_6g_size)

        push!(sim_state.history_mean_entries_6g, mean_entries_6g)
        push!(sim_state.history_median_entries_6g, median_entries_6g)

        @yield timeout(env, 1.0) # Sample every 1.0 time unit
    end
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

function calculate_6g_metrics(state::SimGlobalState)
    # Calculate 6G metrics
    entries_6g = [length(t) for t in state.forwarding_tables_6g]
    
    # Allocated Memory 6G
    mem_6g_allocated_mb = [Base.summarysize(t) / (1024^2) for t in state.forwarding_tables_6g]
    
    # Raw Memory 6G
    # sizeof(ForwardingEntry6GRUPA) is 12 bytes
    element_size_6g = sizeof(ForwardingEntry6GRUPA)
    mem_6g_raw_mb = [length(t) * element_size_6g / (1024^2) for t in state.forwarding_tables_6g]

    mem_per_entry_6g = [length(t) > 0 ? (Base.summarysize(t) / length(t)) : 0.0 for t in state.forwarding_tables_6g]
    
    return DataFrame(
        Entries_6G=entries_6g,
        Total_Mem_6G_MB=mem_6g_allocated_mb,
        Raw_Mem_6G_MB=mem_6g_raw_mb,
        Bytes_Per_Entry_6G=mem_per_entry_6g
    )
end
