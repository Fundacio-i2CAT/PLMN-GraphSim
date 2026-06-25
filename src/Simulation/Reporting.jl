using DataFrames
using CSV
using ..Types

function save_simulation_results(operator_name::String, scenario_name::String, state::SimGlobalState, topology::NetworkTopology)
    # Create results directory if it doesn't exist
    results_dir = joinpath(@__DIR__, "../../results")
    if !isdir(results_dir)
        mkdir(results_dir)
    end
    
    # We no longer save the aggregated simulation_results_*.csv because the statistical fields 
    # (history_total_*, history_mean_*, etc.) have been removed from SimGlobalState.
    # Instead, we only save the detailed evolution in Long Format.
    
    save_detailed_evolution(operator_name, scenario_name, state, topology, results_dir)

    # Mobility metrics are written only when mobility was actually exercised, to
    # avoid cluttering the results dir for legacy stationary runs.
    if state.config.mobility.enabled
        save_mobility_evolution(operator_name, scenario_name, state, results_dir)
    end
end

"""
    save_mobility_evolution(operator_name, scenario_name, state, results_dir)

Persist the per-tick cumulative handover and signaling-cost counters as a
long-form CSV. Columns:
  Time, Handovers_Cumulative, Sigma_5G_Xn, Sigma_5G_N2, Sigma_RUPA_Intra,
  Sigma_RUPA_Inter, Sigma_Roam_5G, Sigma_Roam_RUPA
"""
function save_mobility_evolution(operator_name::String, scenario_name::String,
                                 state::SimGlobalState, results_dir::String)
    df = DataFrame(
        Time = state.history_time,
        Handovers_Cumulative = state.history_handovers,
        Sigma_5G_Xn = state.history_sigma_5g_xn,
        Sigma_5G_N2 = state.history_sigma_5g_n2,
        Sigma_RUPA_Intra = state.history_sigma_rupa_intra,
        Sigma_RUPA_Inter = state.history_sigma_rupa_inter,
        Sigma_Roam_5G = state.history_sigma_roam_5g,
        Sigma_Roam_RUPA = state.history_sigma_roam_rupa,
        CoreWrites_5G = state.history_core_writes_5g,
        CoreWrites_RUPA = state.history_core_writes_rupa,
    )
    safe_op = replace(operator_name, " " => "_")
    safe_scen = replace(scenario_name, " " => "_")
    filename = "mobility_evolution_$(safe_op)_$(safe_scen).csv"
    CSV.write(joinpath(results_dir, filename), df)
    println("  -> Mobility Evolution: results/$filename")
end

# function save_topology_map(operator_name::String, scenario_name::String, topology::NetworkTopology, results_dir::String)
#     if isempty(topology.edge_upf_parent_map)
#         return
#     end
#     
#     # Create DataFrame for Edge UPF -> PSA mapping
#     # Edge UPFs are 1-indexed in the map
#     edge_upfs = 1:length(topology.edge_upf_parent_map)
#     psa_upfs = topology.edge_upf_parent_map
#     
#     df_map = DataFrame(
#         Edge_UPF_ID = edge_upfs,
#         PSA_UPF_ID = psa_upfs
#     )
#     
#     filename = "topology_map_$(operator_name)_$(scenario_name).csv"
#     CSV.write(joinpath(results_dir, filename), df_map)
#     println("  -> Topology Map: results/$filename")
# end

function save_detailed_evolution(operator_name::String, scenario_name::String, state::SimGlobalState, topology::NetworkTopology, results_dir::String)
    times = Float64[]
    upf_ids = Int[]
    tiers = Int[]
    
    entries_5g = Int[]
    mem_5g = Float64[]
    entries_6g = Int[]
    mem_6g = Float64[]
    
    num_steps = length(state.history_time)
    num_edge = length(topology.upf_locations)
    
    for t_idx in 1:num_steps
        time_val = state.history_time[t_idx]
        
        # All vectors should have the same length (number of UPFs) for a given time step
        # We assume they are all synchronized in size
        vals_entries_5g = state.history_per_upf_entries_5g[t_idx]
        vals_mem_5g = state.history_per_upf_5g_fwd_state_info_size_mb[t_idx]
        vals_entries_6g = state.history_per_gupf_entries_6grupa[t_idx]
        vals_mem_6g = state.history_per_gupf_6grupa_fwd_state_info_size_mb[t_idx]
        
        num_upfs = length(vals_entries_5g)
        
        for idx in 1:num_upfs
            push!(times, time_val)
            push!(upf_ids, idx)
            
            # Determine Tier
            if idx <= num_edge
                push!(tiers, 1) # Edge
            else
                push!(tiers, 2) # Centralized / PSA
            end
            
            push!(entries_5g, vals_entries_5g[idx])
            push!(mem_5g, vals_mem_5g[idx])
            push!(entries_6g, vals_entries_6g[idx])
            push!(mem_6g, vals_mem_6g[idx])
        end
    end
    
    df = DataFrame(
        Time = times,
        UPF_ID = upf_ids,
        Tier = tiers,
        Entries_5G = entries_5g,
        Memory_5G_MB = mem_5g,
        Entries_6G = entries_6g,
        Memory_6G_MB = mem_6g
    )
    
    # Replace spaces with underscores in filename to be safe
    safe_op = replace(operator_name, " " => "_")
    safe_scen = replace(scenario_name, " " => "_")
    
    filename = "evolution_detailed_$(safe_op)_$(safe_scen).csv"
    CSV.write(joinpath(results_dir, filename), df)
    println("  -> Detailed Evolution: results/$filename")
end

function print_forwarding_tables(state::SimGlobalState, scale_factor::Int)
    println("\n--- Detailed Forwarding State Dump ---")
    println("\n[5G Architecture] Per-UPF Session Contexts (Dynamic State):")
    for (i, sessions) in enumerate(state.upf_sessions_5g)
        mem_mb = Base.summarysize(sessions) / (1024^2)
        num_sessions = length(sessions)
        # We agreggate calculations just by scaling the number of sessions.
        # Each session has 2 entries (UL + DL)
        real_entries = num_sessions * scale_factor * 2
        real_mem_mb = mem_mb * scale_factor
        println("  UPF #$i:")
        println("    Forwarding Entries: $real_entries (Active PDU Sessions * 2)")
        println("    Memory Usage:       $(round(real_mem_mb, digits=4)) MB")
    end

    println("\n[6G-RUPA Architecture] GUPF Forwarding Tables (Static/Topological State):")
    for (i, table) in enumerate(state.forwarding_tables_6grupa)
        mem_mb = Base.summarysize(table) / (1024^2)
        num_entries = length(table)
        println("  GUPF #$i:")
        println("    Forwarding Entries: $num_entries")
        println("    Memory Usage:       $(round(mem_mb, digits=6)) MB")
    end
end
