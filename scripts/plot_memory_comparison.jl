using CSV
using DataFrames
using Plots
using StatsPlots
using Printf
using Statistics

# Set default plot size and font
default(size=(800, 600), guidefont=12, tickfont=10, legendfont=10)

function load_raw_data()
    results_dir = joinpath(@__DIR__, "../results")
    files = readdir(results_dir)
    raw_files = filter(f -> startswith(f, "raw_upf_state_") && endswith(f, ".csv"), files)
    
    all_data = DataFrame()
    
    for file in raw_files
        # Filename format: raw_upf_state_Operator_Scenario.csv
        # Example: raw_upf_state_Vodafone_Centralized.csv
        parts = split(replace(file, ".csv" => ""), "_")
        # parts: ["raw", "upf", "state", "Operator", "Scenario"]
        operator = parts[4]
        scenario = parts[5]
        
        df = CSV.read(joinpath(results_dir, file), DataFrame)
        df.Operator .= operator
        df.Scenario .= scenario
        df.Architecture_Scenario .= "$operator - $scenario"
        
        append!(all_data, df)
    end
    
    return all_data
end

function plot_total_memory_comparison(df::DataFrame)
    println("Generating Total Memory Comparison Plot...")
    
    # Group by Operator and Scenario
    grouped = combine(groupby(df, [:Operator, :Scenario]), 
        :Total_Mem_5G_MB => sum => :Allocated_5G,
        :Raw_Mem_5G_MB => sum => :Used_5G,
        :Total_Mem_6G_MB => sum => :Allocated_6G,
        :Raw_Mem_6G_MB => sum => :Used_6G
    )
    
    # Prepare data for plotting
    # Create a long format for StatsPlots
    long_df = stack(grouped, [:Allocated_5G, :Used_5G, :Allocated_6G, :Used_6G], variable_name=:Metric, value_name=:Memory_MB)
    long_df.Label = long_df.Operator .* "\n" .* long_df.Scenario
    
    p = groupedbar(long_df.Label, long_df.Memory_MB, group=long_df.Metric,
        ylabel="Total Network Memory (MB)",
        title="Total Network Memory: Allocated vs Used",
        bar_width=0.8,
        lw=0,
        framestyle=:box,
        yscale=:log10, # Log scale is crucial here
        legend=:outertopright,
        margin=10Plots.mm,
        size=(1000, 600)
    )
    
    savefig(p, joinpath(@__DIR__, "../images/total_memory_comparison.png"))
end

function plot_per_upf_statistics(df::DataFrame)
    println("Generating Per-UPF Statistics Plots...")
    
    # Group by Operator and Scenario
    # Calculate stats for Allocated and Used memory
    grouped = combine(groupby(df, [:Operator, :Scenario]), 
        :Total_Mem_5G_MB => mean => :Avg_Alloc_5G,
        :Total_Mem_5G_MB => median => :Med_Alloc_5G,
        :Total_Mem_5G_MB => maximum => :Max_Alloc_5G,
        :Total_Mem_5G_MB => minimum => :Min_Alloc_5G,
        
        :Raw_Mem_5G_MB => mean => :Avg_Used_5G,
        :Raw_Mem_5G_MB => median => :Med_Used_5G,
        :Raw_Mem_5G_MB => maximum => :Max_Used_5G,
        :Raw_Mem_5G_MB => minimum => :Min_Used_5G,
        
        :Total_Mem_6G_MB => mean => :Avg_Alloc_6G,
        :Total_Mem_6G_MB => median => :Med_Alloc_6G,
        :Total_Mem_6G_MB => maximum => :Max_Alloc_6G,
        :Total_Mem_6G_MB => minimum => :Min_Alloc_6G,
        
        :Raw_Mem_6G_MB => mean => :Avg_Used_6G,
        :Raw_Mem_6G_MB => median => :Med_Used_6G,
        :Raw_Mem_6G_MB => maximum => :Max_Used_6G,
        :Raw_Mem_6G_MB => minimum => :Min_Used_6G
    )

    # Helper to plot a specific statistic
    function create_stat_plot(stat_name, col_suffix, title_suffix)
        cols = [
            Symbol("$(col_suffix)_Alloc_5G"), 
            Symbol("$(col_suffix)_Used_5G"), 
            Symbol("$(col_suffix)_Alloc_6G"), 
            Symbol("$(col_suffix)_Used_6G")
        ]
        
        long_df = stack(grouped, cols, variable_name=:Metric, value_name=:Memory_MB)
        long_df.Label = long_df.Operator .* "\n" .* long_df.Scenario
        
        # Clean up metric names for legend
        long_df.Metric = replace.(string.(long_df.Metric), "$(col_suffix)_" => "")
        
        p = groupedbar(long_df.Label, long_df.Memory_MB, group=long_df.Metric,
            ylabel="$stat_name Memory per UPF (MB)",
            title="$stat_name Memory per UPF: $title_suffix",
            bar_width=0.8,
            lw=0,
            framestyle=:box,
            yscale=:log10,
            legend=:outertopright,
            margin=10Plots.mm,
            size=(1000, 600)
        )
        return p
    end

    # Generate plots for Average, Median, Max, Min
    p_avg = create_stat_plot("Average", "Avg", "Allocated vs Used")
    savefig(p_avg, joinpath(@__DIR__, "../images/average_memory_per_upf.png"))
    
    p_med = create_stat_plot("Median", "Med", "Allocated vs Used")
    savefig(p_med, joinpath(@__DIR__, "../images/median_memory_per_upf.png"))
    
    p_max = create_stat_plot("Maximum", "Max", "Bottleneck Analysis")
    savefig(p_max, joinpath(@__DIR__, "../images/max_memory_per_upf.png"))

    p_min = create_stat_plot("Minimum", "Min", "Baseline Load")
    savefig(p_min, joinpath(@__DIR__, "../images/min_memory_per_upf.png"))
end

function main()
    # Ensure images directory exists
    if !isdir(joinpath(@__DIR__, "../images"))
        mkdir(joinpath(@__DIR__, "../images"))
    end
    
    data = load_raw_data()
    println("Loaded $(nrow(data)) rows of UPF data.")
    
    plot_total_memory_comparison(data)
    plot_per_upf_statistics(data)
    
    println("All plots generated in images/ directory.")
end

main()
