using DataFrames
using CSV
using ..Types

function save_simulation_results(operator_name::String, scenario_name::String, state::SimGlobalState)
    df = DataFrame(
        Time=state.history_time,
        Total_5G_MB=state.history_total_5g_mb,
        Max_UPF_5G_MB=state.history_max_upf_5g_mb,
        Mean_UPF_5G_MB=state.history_mean_upf_5g_mb,
        Median_UPF_5G_MB=state.history_median_upf_5g_mb,
        
        Total_6G_MB=state.history_total_6g_mb,
        Max_UPF_6G_MB=state.history_max_upf_6g_mb,
        Mean_UPF_6G_MB=state.history_mean_upf_6g_mb,
        Median_UPF_6G_MB=state.history_median_upf_6g_mb,

        Mean_Entries_6G=state.history_mean_entries_6g,
        Median_Entries_6G=state.history_median_entries_6g
    )
    # Create results directory if it doesn't exist
    results_dir = joinpath(@__DIR__, "../../results")
    if !isdir(results_dir)
        mkdir(results_dir)
    end
    filename = "simulation_results_$(operator_name)_$(scenario_name).csv"
    CSV.write(joinpath(results_dir, filename), df)
    println("  -> Results: results/$filename")
end

function save_raw_upf_data(operator_name::String, scenario_name::String, state::SimGlobalState, scale_factor::Int)
    # Calculate metrics separately
    df_5g = calculate_5g_metrics(state, scale_factor)
    df_6g = calculate_6g_metrics(state)
    
    # Combine DataFrames (assuming row alignment which is guaranteed by initialization)
    df = hcat(df_5g, df_6g)
    
    results_dir = joinpath(@__DIR__, "../../results")
    if !isdir(results_dir)
        mkdir(results_dir)
    end
    filename = "raw_upf_state_$(operator_name)_$(scenario_name).csv"
    CSV.write(joinpath(results_dir, filename), df)
    println("  -> Raw Data: results/$filename")
end

function print_forwarding_tables(state::SimGlobalState, scale_factor::Int)
    println("\n--- Detailed Forwarding State Dump ---")
    println("\n[5G Architecture] Per-UPF Session Contexts (Dynamic State):")
    for (i, sessions) in enumerate(state.upf_sessions_5g)
        mem_mb = Base.summarysize(sessions) / (1024^2)
        num_entries = length(sessions)
        # We agreggate calculations just by scaling the number of sessions.
        real_entries = num_entries * scale_factor
        real_mem_mb = mem_mb * scale_factor
        println("  UPF #$i:")
        println("    Forwarding Entries: $real_entries (Active PDU Sessions)")
        println("    Memory Usage:       $(round(real_mem_mb, digits=4)) MB")
    end

    println("\n[6G-RUPA Architecture] GUPF Forwarding Tables (Static/Topological State):")
    for (i, table) in enumerate(state.forwarding_tables_6g)
        mem_mb = Base.summarysize(table) / (1024^2)
        num_entries = length(table)
        println("  GUPF #$i:")
        println("    Forwarding Entries: $num_entries")
        println("    Memory Usage:       $(round(mem_mb, digits=6)) MB")
    end
end
