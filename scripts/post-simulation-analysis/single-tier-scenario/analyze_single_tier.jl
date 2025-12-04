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
IMAGES_DIR = joinpath(@__DIR__, "../../../docs/images/single_tier_scenario")
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
    p_mem_5g = get_evolution_plot(df, :Memory_5G_MB, "Memory Evolution (5G)", "Memory (MB)")
    
    # 2. Memory 6G
    p_mem_6g = get_evolution_plot(df, :Memory_6G_MB, "Memory Evolution (6G-RUPA)", "Memory (MB)")
    
    # 3. Entries 5G
    p_ent_5g = get_evolution_plot(df, :Entries_5G, "Entries Evolution (5G)", "Entries", force_scientific=true)
    
    # 4. Entries 6G
    p_ent_6g = get_evolution_plot(df, :Entries_6G, "Entries Evolution (6G-RUPA)", "Entries", force_scientific=true)
    
    # Combine
    dashboard = plot(p_mem_5g, p_mem_6g, p_ent_5g, p_ent_6g, 
        layout=(2, 2), 
        size=(1200, 800),
        plot_title="Evolution Dashboard: $config_name",
        plot_titlefontsize=16
    )
    
    safe_config = replace(config_name, " " => "_")
    outfile = joinpath(output_dir, "dashboard_evolution_$(safe_config).png")
    savefig(dashboard, outfile)
    return basename(outfile)
end

function generate_global_stats_dashboard(df::DataFrame, output_dir::String)
    println("Generating Global Stats Dashboard...")
    
    # 1. Total Memory Comparison (Bar)
    grouped_mem = combine(groupby(df, [:Operator, :Scenario]), 
        :Total_5G_FwdStateInfoSize_MB => sum => :Memory_5G,
        :Total_6GRUPA_FwdStateInfoSize_MB => sum => :Memory_6G
    )
    long_mem = stack(grouped_mem, [:Memory_5G, :Memory_6G], variable_name=:Metric, value_name=:Memory_MB)
    long_mem.Label = long_mem.Operator
    
    p1 = groupedbar(long_mem.Label, long_mem.Memory_MB, group=long_mem.Metric,
        ylabel="Total Memory (MB)",
        title="Total Network Memory (Log Scale)",
        yscale=:log10,
        legend=:topleft
    )

    # 2. Average Memory per UPF (Bar)
    grouped_avg = combine(groupby(df, [:Operator, :Scenario]), 
        :Total_5G_FwdStateInfoSize_MB => mean => :Avg_Mem_5G,
        :Total_6GRUPA_FwdStateInfoSize_MB => mean => :Avg_Mem_6G
    )
    long_avg = stack(grouped_avg, [:Avg_Mem_5G, :Avg_Mem_6G], variable_name=:Metric, value_name=:Memory_MB)
    long_avg.Label = long_avg.Operator
    
    p2 = groupedbar(long_avg.Label, long_avg.Memory_MB, group=long_avg.Metric,
        ylabel="Avg Memory (MB)",
        title="Average Memory per UPF (Log Scale)",
        yscale=:log10,
        legend=:topleft
    )

    # 3. Box Plot of Table Sizes
    df_5g = select(df, :Operator, :Entries_5G => :Entries)
    df_5g.Architecture .= "5G"
    df_6g = select(df, :Operator, :Entries_6GRUPA => :Entries)
    df_6g.Architecture .= "6G-RUPA"
    long_box = vcat(df_5g, df_6g)
    
    p3 = groupedboxplot(long_box.Operator, long_box.Entries, group=long_box.Architecture,
        ylabel="Entries",
        title="Distribution of Table Sizes (Log Scale)",
        yscale=:log10,
        legend=:topleft
    )

    # 4. Memory Reduction Factor
    grouped_red = combine(groupby(df, :Configuration), 
        :Total_5G_FwdStateInfoSize_MB => sum => :Total_5G,
        :Total_6GRUPA_FwdStateInfoSize_MB => sum => :Total_6G
    )
    grouped_red.Reduction = grouped_red.Total_5G ./ grouped_red.Total_6G
    # Extract Operator from Configuration (assuming "Operator_Country_Scenario")
    grouped_red.Operator = [split(c, "_")[1] for c in grouped_red.Configuration]

    p4 = bar(grouped_red.Operator, grouped_red.Reduction,
        ylabel="Factor (x)",
        title="Memory Reduction Factor (5G / 6G)",
        legend=false,
        color=:green
    )
    
    dashboard = plot(p1, p2, p3, p4, 
        layout=(2, 2), 
        size=(1200, 800),
        plot_title="Global Statistics Dashboard",
        plot_titlefontsize=16,
        margin=5Plots.mm
    )
    
    outfile = joinpath(output_dir, "dashboard_global_stats.png")
    savefig(dashboard, outfile)
    return basename(outfile)
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
