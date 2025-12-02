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
        Total_6GRUPA_MB=state.history_total_6grupa_mb,
        Max_GUPF_6GRUPA_MB=state.history_max_gupf_6grupa_mb,
        Mean_GUPF_6GRUPA_MB=state.history_mean_gupf_6grupa_mb,
        Median_GUPF_6GRUPA_MB=state.history_median_gupf_6grupa_mb,
        Mean_Entries_6GRUPA=state.history_mean_entries_6grupa,
        Median_Entries_6GRUPA=state.history_median_entries_6grupa
    )
    # Create results directory if it doesn't exist
    results_dir = joinpath(@__DIR__, "../../results")
    if !isdir(results_dir)
        mkdir(results_dir)
    end
    filename = "simulation_results_$(operator_name)_$(scenario_name).csv"
    CSV.write(joinpath(results_dir, filename), df)
    println("  -> Results: results/$filename")
    save_detailed_evolution(operator_name, scenario_name, state, results_dir)
end

function save_detailed_evolution(operator_name::String, scenario_name::String, state::SimGlobalState, results_dir::String)
    # Helper to save a matrix (Time x UPF)
    function save_matrix(data::Vector{Vector{T}}, metric_name::String) where T
        if isempty(data)
            return
        end
        
        # Convert Vector of Vectors to Matrix
        # Rows: Time steps
        # Cols: UPFs
        num_rows = length(data)
        num_cols = length(data[1])
        
        # Create DataFrame
        # Time column
        df_detailed = DataFrame(Time=state.history_time)
        
        # UPF columns
        for i in 1:num_cols
            col_name = "UPF_$(i)"
            df_detailed[!, col_name] = [row[i] for row in data]
        end
        
        filename = "evolution_$(metric_name)_$(operator_name)_$(scenario_name).csv"
        CSV.write(joinpath(results_dir, filename), df_detailed)
        println("  -> Detailed Evolution ($metric_name): results/$filename")
    end

    save_matrix(state.history_per_upf_5g_mb, "5g_mb")
    save_matrix(state.history_per_upf_entries_5g, "5g_entries")
    save_matrix(state.history_per_gupf_6grupa_mb, "6grupa_mb")
    save_matrix(state.history_per_gupf_entries_6grupa, "6grupa_entries")
end

function save_raw_upf_data(operator_name::String, scenario_name::String, state::SimGlobalState, scale_factor::Int)
    # Calculate metrics separately
    df_5g = calculate_5g_metrics(state, scale_factor)
    df_6grupa = calculate_6grupa_metrics(state)
    
    # Combine DataFrames (assuming row alignment which is guaranteed by initialization)
    df = hcat(df_5g, df_6grupa)
    
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
    for (i, table) in enumerate(state.forwarding_tables_6grupa)
        mem_mb = Base.summarysize(table) / (1024^2)
        num_entries = length(table)
        println("  GUPF #$i:")
        println("    Forwarding Entries: $num_entries")
        println("    Memory Usage:       $(round(mem_mb, digits=6)) MB")
    end
end
