using ConcurrentSim
using ResumableFunctions
using Dates
using DataFrames
using Statistics
using ..Types

include("5G.jl")
include("6GRUPA.jl")

@resumable function monitor_metrics(env, sim_state::SimGlobalState)
    while true
        current_time = now(env)
        metrics_5g = collect_5g_metrics(sim_state)
        metrics_6grupa = collect_6grupa_metrics(sim_state)
        update_history!(sim_state, current_time, metrics_5g, metrics_6grupa)
        @yield timeout(env, 1.0) # Sample every 1.0 time unit
    end
end

function update_history!(sim_state, current_time, metrics_5g, metrics_6grupa)
    push!(sim_state.history_time, current_time)
    push!(sim_state.history_total_5g_mb, metrics_5g.total)
    push!(sim_state.history_max_upf_5g_mb, metrics_5g.max)
    push!(sim_state.history_mean_upf_5g_mb, metrics_5g.mean)
    push!(sim_state.history_median_upf_5g_mb, metrics_5g.median)
    push!(sim_state.history_total_6grupa_mb, metrics_6grupa.total)
    push!(sim_state.history_max_gupf_6grupa_mb, metrics_6grupa.max)
    push!(sim_state.history_mean_gupf_6grupa_mb, metrics_6grupa.mean)
    push!(sim_state.history_median_gupf_6grupa_mb, metrics_6grupa.median)
    push!(sim_state.history_mean_entries_6grupa, metrics_6grupa.mean_entries)
    push!(sim_state.history_median_entries_6grupa, metrics_6grupa.median_entries)
    push!(sim_state.history_per_upf_5g_mb, copy(metrics_5g.per_upf_mb))
    push!(sim_state.history_per_upf_entries_5g, copy(metrics_5g.per_upf_entries))
    push!(sim_state.history_per_gupf_6grupa_mb, copy(metrics_6grupa.per_gupf_mb))
    push!(sim_state.history_per_gupf_entries_6grupa, copy(metrics_6grupa.per_gupf_entries))
end
