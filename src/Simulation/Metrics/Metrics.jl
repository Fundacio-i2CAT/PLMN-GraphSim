using ConcurrentSim
using ResumableFunctions
using Dates
using DataFrames
using Statistics
using ..Types

include("5G.jl")
include("6GRUPA.jl")

@resumable function monitor_metrics(env, sim_state::SimGlobalState, topology::NetworkTopology, scale_factor::Int)
    while true
        current_time = now(env)
        metrics_5g = collect_5g_metrics(sim_state, topology, scale_factor)
        metrics_6grupa = collect_6grupa_metrics(sim_state)
        update_history!(sim_state, current_time, metrics_5g, metrics_6grupa)
        @yield timeout(env, sim_state.config.sampling_interval)
    end
end

function update_history!(sim_state, current_time, metrics_5g, metrics_6grupa)
    push!(sim_state.history_time, current_time)
    push!(sim_state.history_per_upf_5g_fwd_state_info_size_mb, copy(metrics_5g.per_upf_fwd_state_info_size_mb))
    push!(sim_state.history_per_upf_entries_5g, copy(metrics_5g.per_upf_entries))
    
    # 6G: We should also combine Edge and Centralized GUPFs if we want consistency
    # But for now, let's just update the 5G part as requested.
    # Wait, if we removed the fields from SimGlobalState, we MUST update this.
    
    # Combine 6G Edge and Centralized for consistency with the new SimGlobalState structure
    all_6g_mb = vcat(metrics_6grupa.per_gupf_fwd_state_info_size_mb, metrics_6grupa.per_centralized_gupf_fwd_state_info_size_mb)
    all_6g_entries = vcat(metrics_6grupa.per_gupf_entries, metrics_6grupa.per_centralized_gupf_entries)
    
    push!(sim_state.history_per_gupf_6grupa_fwd_state_info_size_mb, all_6g_mb)
    push!(sim_state.history_per_gupf_entries_6grupa, all_6g_entries)
end
