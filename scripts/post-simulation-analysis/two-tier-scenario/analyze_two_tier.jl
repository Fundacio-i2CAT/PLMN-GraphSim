using CSV
using DataFrames
using Plots
using StatsPlots
using Statistics
using Printf
using Dates

# Include Common Utils
include("../common/Utils.jl")
using .Utils

# --- Configuration ---
SCENARIO_NAME = "two-tier"
SCENARIO_FILTER = "TwoTier" 

IMAGES_DIR = joinpath(@__DIR__, "../../../images/two_tier_scenario")
if !isdir(IMAGES_DIR)
    mkpath(IMAGES_DIR)
end

# --- Analysis Functions ---

function get_combined_evolution_plot(df::DataFrame, col_5g::Symbol, col_6g::Symbol, title::String, ylabel::String; force_scientific::Bool=false)
    # Explicit Colors (Wong's Palette)
    c_5g = colorant"#E69F00" # Orange
    c_6g = colorant"#56B4E9" # Sky Blue
    
    p = plot(
        xlabel="Time (s)",
        ylabel=ylabel,
        title=title,
        legend=:outertop,
        framestyle=:box,
        margin=5Plots.mm,
        titlefontsize=10,
        guidefontsize=8,
        tickfontsize=8,
        yformatter = force_scientific ? :scientific : :auto,
        yscale=:log10
    )
    
    upf_ids = unique(df.UPF_ID)
    first_5g = true
    first_6g = true
    
    for upf in upf_ids
        sub_df = filter(row -> row.UPF_ID == upf, df)
        
        # Data cleaning for log plot (replace <= 0 with NaN)
        y_5g = map(x -> x <= 0 ? NaN : x, sub_df[!, col_5g])
        y_6g = map(x -> x <= 0 ? NaN : x, sub_df[!, col_6g])
        
        # Only label the first line of each type
        lbl_5g = first_5g ? "5G UPFs" : nothing
        lbl_6g = first_6g ? "6G-RUPA GUPFs" : nothing
        
        plot!(p, sub_df.Time, y_5g, color=c_5g, alpha=0.3, lw=1.5, label=lbl_5g)
        plot!(p, sub_df.Time, y_6g, color=c_6g, alpha=0.3, lw=1.5, label=lbl_6g)
        
        if first_5g; first_5g = false; end
        if first_6g; first_6g = false; end
    end
    
    # Mean lines
    mean_5g = combine(groupby(df, :Time), col_5g => mean => :Mean)
    mean_6g = combine(groupby(df, :Time), col_6g => mean => :Mean)
    
    y_mean_5g = map(x -> x <= 0 ? NaN : x, mean_5g.Mean)
    y_mean_6g = map(x -> x <= 0 ? NaN : x, mean_6g.Mean)
    
    plot!(p, mean_5g.Time, y_mean_5g, label="Mean 5G", color=c_5g, lw=3, linestyle=:solid)
    plot!(p, mean_6g.Time, y_mean_6g, label="Mean 6G-RUPA", color=c_6g, lw=3, linestyle=:solid)
    
    return p
end

function generate_scenario_dashboard(config_name::String, detailed_file::String, output_dir::String)
    println("Generating Dashboard for $config_name...")
    df = CSV.read(detailed_file, DataFrame)
    
    # Filter for Centralized UPFs (Tier 2)
    df_centralized = filter(row -> row.Tier == 2, df)
    
    if nrow(df_centralized) == 0
        println("  Warning: No Tier 2 (Centralized) UPFs found for $config_name")
        return
    end

    # 1. Memory Comparison
    p_mem = get_combined_evolution_plot(df_centralized, :Memory_5G_MB, :Memory_6G_MB, 
        "Memory Evolution (Centralized UPFs)", "Memory (MB)")
    
    # 2. Entries Comparison
    p_ent = get_combined_evolution_plot(df_centralized, :Entries_5G, :Entries_6G, 
        "Entries Evolution (Centralized UPFs)", "Entries", force_scientific=true)
    
    # Combine
    dashboard = plot(p_mem, p_ent, 
        layout=(1, 2), 
        size=(1200, 600),
        plot_title="Centralized UPF Evolution: $config_name",
        plot_titlefontsize=16,
        margin=10Plots.mm
    )
    
    safe_config = replace(config_name, " " => "_")
    outfile = joinpath(output_dir, "dashboard_evolution_$(safe_config).pdf")
    savefig(dashboard, outfile)
    return basename(outfile)
end

function generate_global_stats_dashboard(df::DataFrame, output_dir::String)
    println("Generating Global Stats Dashboard...")
    
    # --- Sorting Logic ---
    # Helper to extract country
    function get_country(config)
        parts = split(config, "_")
        return length(parts) >= 2 ? parts[2] : "ZZZ"
    end
    
    # Create Order Mapping based on Country then Operator
    unique_configs = unique(select(df, :Operator, :Configuration))
    unique_configs.Country = get_country.(unique_configs.Configuration)
    sort!(unique_configs, [:Country, :Operator])
    
    operator_order = Dict(op => i for (i, op) in enumerate(unique_configs.Operator))
    ordered_labels = unique_configs.Operator
    # ---------------------

    # 1. Total Memory Comparison (Bar)
    grouped_mem = combine(groupby(df, [:Operator, :Scenario]), 
        :Total_5G_FwdStateInfoSize_MB => sum => :Memory_5G,
        :Total_6GRUPA_FwdStateInfoSize_MB => sum => :Memory_6G
    )
    long_mem = stack(grouped_mem, [:Memory_5G, :Memory_6G], variable_name=:Metric, value_name=:Memory_MB)
    # Use Order Index
    long_mem.Order = [operator_order[op] for op in long_mem.Operator]
    # Rename metrics for consistent legend
    long_mem.Metric = replace.(string.(long_mem.Metric), "Memory_5G" => "5G", "Memory_6G" => "6G-RUPA")
    
    p1 = groupedbar(long_mem.Order, long_mem.Memory_MB, group=long_mem.Metric,
        ylabel="Total Memory (MB)",
        title="Total Forwarding State Memory (Log Scale)",
        yscale=:log10,
        legend=:topleft,
        xticks=(1:length(ordered_labels), ordered_labels),
        xrotation=45,
        bottom_margin=15Plots.mm
    )

    # 2. Total Entries Comparison (Bar)
    grouped_entries = combine(groupby(df, [:Operator, :Scenario]), 
        :Entries_5G => sum => :Entries_5G,
        :Entries_6GRUPA => sum => :Entries_6G
    )
    long_entries = stack(grouped_entries, [:Entries_5G, :Entries_6G], variable_name=:Metric, value_name=:Entries)
    # Use Order Index
    long_entries.Order = [operator_order[op] for op in long_entries.Operator]
    # Rename metrics for consistent legend
    long_entries.Metric = replace.(string.(long_entries.Metric), "Entries_5G" => "5G", "Entries_6G" => "6G-RUPA")
    
    p2 = groupedbar(long_entries.Order, long_entries.Entries, group=long_entries.Metric,
        ylabel="Total Entries",
        title="Total Number of Entries (Log Scale)",
        yscale=:log10,
        legend=false,
        xticks=(1:length(ordered_labels), ordered_labels),
        xrotation=45,
        bottom_margin=15Plots.mm
    )

    # 3. Violin Plot of Table Sizes (Tier 2 Only)
    if "Tier" in names(df)
        df_tier2 = filter(row -> row.Tier == 2, df)
    else
        df_tier2 = df
    end

    df_5g = select(df_tier2, :Operator, :Entries_5G => :Entries)
    df_5g.Architecture .= "5G"
    df_6g = select(df_tier2, :Operator, :Entries_6GRUPA => :Entries)
    df_6g.Architecture .= "6G-RUPA"
    long_box = vcat(df_5g, df_6g)
    # Use Order Index
    long_box.Order = [operator_order[op] for op in long_box.Operator]
    
    p3 = groupedviolin(long_box.Order, long_box.Entries, group=long_box.Architecture,
        ylabel="Entries",
        title="Distribution of Table Sizes (Centralized UPFs) (Log Scale)",
        yscale=:log10,
        legend=false,
        xticks=(1:length(ordered_labels), ordered_labels),
        xrotation=45,
        bottom_margin=15Plots.mm
    )

    # Combine
    l = @layout [a b; c{0.6h}]
    dashboard = plot(p1, p2, p3, 
        layout=l, 
        size=(1200, 1000),
        # plot_title="Global Statistics Dashboard",
        plot_titlefontsize=16,
        margin=5Plots.mm
    )
    
    outfile = joinpath(output_dir, "dashboard_global_stats.pdf")
    savefig(dashboard, outfile)
    return basename(outfile)
end

function print_summary_table(df::DataFrame)
    println("\n--- Summary Table (Centralized UPFs / Tier 2) ---")
    
    # Filter for Tier 2
    if "Tier" in names(df)
        df_tier2 = filter(row -> row.Tier == 2, df)
    else
        println("Warning: 'Tier' column not found in dataframe. Using all UPFs.")
        df_tier2 = df
    end
    
    grouped = groupby(df_tier2, :Configuration)
    
    println("| Configuration | Total 5G Mem (MB) | Total 6G-RUPA Mem (MB) | Reduction Factor | Max 5G Entries | Max 6G Entries |")
    println("|---|---|---|---|---|---|")
    
    for key in keys(grouped)
        sub_df = grouped[key]
        config = key.Configuration
        
        total_mem_5g = sum(sub_df.Total_5G_FwdStateInfoSize_MB)
        total_mem_6g = sum(sub_df.Total_6GRUPA_FwdStateInfoSize_MB)
        reduction = total_mem_5g / total_mem_6g
        
        max_entries_5g = maximum(sub_df.Entries_5G)
        max_entries_6g = maximum(sub_df.Entries_6GRUPA)
        
        @printf("| %s | %.2f | %.2f | **%.1fx** | %d | %d |\n", 
            config, total_mem_5g, total_mem_6g, reduction, max_entries_5g, max_entries_6g)
    end
    println("---------------------------------------------------\n")
end

function main()
    set_default_plot_style()
    results_dir = get_results_dir()
    
    println("Results Dir: $results_dir")
    println("Images Dir: $IMAGES_DIR")
    
    # 1. Load Data (Last time step summary)
    all_data = load_raw_data()
    df = filter(row -> occursin(SCENARIO_FILTER, row.Configuration), all_data)
    
    if nrow(df) == 0
        println("No data found.")
        return
    end
    
    # 2. Generate Global Stats Dashboard
    generate_global_stats_dashboard(df, IMAGES_DIR)
    
    # 3. Print Summary Table
    print_summary_table(df)
    
    # 4. Generate Per-Scenario Evolution Dashboards
    configs = unique(df.Configuration)
    
    for config in configs
        f_detailed = joinpath(results_dir, "evolution_detailed_$(config).csv")
        if isfile(f_detailed)
            generate_scenario_dashboard(config, f_detailed, IMAGES_DIR)
        end
    end
    
    println("Analysis Complete.")
end

main()
