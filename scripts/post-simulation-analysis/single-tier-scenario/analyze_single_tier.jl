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
SCENARIO_NAME = "single-tier"
SCENARIO_FILTER = "Distributed" 

# Override images dir to point to docs
IMAGES_DIR = joinpath(@__DIR__, "../../images/single_tier_scenario")
if !isdir(IMAGES_DIR)
    mkpath(IMAGES_DIR)
end

# --- Analysis Functions ---

function get_evolution_plot(df::DataFrame, col_sym::Symbol, title::String, ylabel::String, is_log::Bool=false; force_scientific::Bool=false)
    p = plot(
        xlabel="Time (s)",
        ylabel=ylabel,
        title=title,
        legend=false,
        framestyle=:box,
        margin=5Plots.mm,
        titlefontsize=10,
        guidefontsize=8,
        tickfontsize=8,
        yformatter = force_scientific ? :scientific : :auto
    )
    
    if is_log
        plot!(p, yscale=:log10)
    end
    
    upf_ids = unique(df.UPF_ID)
    for upf in upf_ids
        sub_df = filter(row -> row.UPF_ID == upf, df)
        plot!(p, sub_df.Time, sub_df[!, col_sym], alpha=0.7, lw=2, label=nothing)
    end
    
    # Mean line
    mean_df = combine(groupby(df, :Time), col_sym => mean => :Mean)
    plot!(p, mean_df.Time, mean_df.Mean, label="Mean", color=:black, lw=4, linestyle=:dash)
    
    return p
end

function generate_scenario_dashboard(config_name::String, detailed_file::String, output_dir::String)
    println("Generating Dashboard for $config_name...")
    df = CSV.read(detailed_file, DataFrame)
    
    # 1. Memory 5G
    p_mem_5g = get_evolution_plot(df, :Memory_5G_MB, "Memory Evolution per UPF (5G)", "Memory (MB)")
    
    # 2. Memory 6G
    p_mem_6g = get_evolution_plot(df, :Memory_6G_MB, "Memory Evolution per GUPF (6G-RUPA)", "Memory (MB)")
    
    # 3. Entries 5G
    p_ent_5g = get_evolution_plot(df, :Entries_5G, "Entries Evolution per UPF (5G)", "Entries", force_scientific=true)
    
    # 4. Entries 6G
    p_ent_6g = get_evolution_plot(df, :Entries_6G, "Entries Evolution per GUPF (6G-RUPA)", "Entries", force_scientific=true)
    
    # Combine
    dashboard = plot(p_mem_5g, p_mem_6g, p_ent_5g, p_ent_6g, 
        layout=(2, 2), 
        size=(1200, 800),
        dpi=300,
        plot_title="Data Across Simulation: $config_name",
        plot_titlefontsize=16
    )
    
    safe_config = replace(config_name, " " => "_")
    outfile_pdf = joinpath(output_dir, "dashboard_evolution_$(safe_config).pdf")
    savefig(dashboard, outfile_pdf)
    outfile_png = joinpath(output_dir, "dashboard_evolution_$(safe_config).png")
    savefig(dashboard, outfile_png)
    return basename(outfile_pdf)
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
    
    # Handle Log Scale 0s
    long_mem.Memory_MB = map(x -> x <= 0 ? NaN : x, long_mem.Memory_MB)

    p1 = groupedbar(long_mem.Order, long_mem.Memory_MB, group=long_mem.Metric,
        ylabel="Total Memory (MB)",
        title="Total Forwarding State Memory (Log Scale)",
        yscale=:log10,
        legend=:outertop,
        legend_columns=-1,
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
    
    # Handle Log Scale 0s
    long_entries.Entries = map(x -> x <= 0 ? NaN : x, long_entries.Entries)

    p2 = groupedbar(long_entries.Order, long_entries.Entries, group=long_entries.Metric,
        ylabel="Total Entries",
        title="Total Number of Entries (Log Scale)",
        yscale=:log10,
        legend=:outertop,
        legend_columns=-1,
        xticks=(1:length(ordered_labels), ordered_labels),
        xrotation=45,
        bottom_margin=15Plots.mm
    )

    # 3. Box Plot of Table Sizes (All UPFs)
    df_5g = select(df, :Operator, :Entries_5G => :Entries)
    df_5g.Architecture .= "5G"
    df_6g = select(df, :Operator, :Entries_6GRUPA => :Entries)
    df_6g.Architecture .= "6G-RUPA"
    long_box = vcat(df_5g, df_6g)
    # Use Order Index
    long_box.Order = [operator_order[op] for op in long_box.Operator]
    
    # Handle Log Scale 0s (Filter them out for Box Plot to avoid Quantile errors)
    filter!(row -> row.Entries > 0, long_box)

    p3 = groupedboxplot(long_box.Order, long_box.Entries, group=long_box.Architecture,
        ylabel="Entries",
        title="Distribution of Table Sizes (All UPFs) (Log Scale)",
        yscale=:log10,
        legend=:outertop,
        legend_columns=-1,
        xticks=(1:length(ordered_labels), ordered_labels),
        xrotation=45,
        bottom_margin=15Plots.mm
    )

    # Combine
    l = @layout [a b; c{0.6h}]
    
    dashboard = plot(p1, p2, p3, 
        layout=l, 
        size=(1000, 1200),
        dpi=300,
        # plot_title="Global Statistics Dashboard (Single Tier)",
        plot_titlefontsize=16,
        margin=5Plots.mm
    )
    
    outfile_pdf = joinpath(output_dir, "dashboard_global_stats.pdf")
    savefig(dashboard, outfile_pdf)
    outfile_png = joinpath(output_dir, "dashboard_global_stats.png")
    savefig(dashboard, outfile_png)
    return basename(outfile_pdf)
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
    
    # 3. Generate Per-Scenario Evolution Dashboards
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
