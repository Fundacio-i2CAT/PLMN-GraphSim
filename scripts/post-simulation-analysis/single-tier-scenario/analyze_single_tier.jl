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
# We filter for "Distributed" because that corresponds to the Single Tier scenario in our results
SCENARIO_FILTER = "Distributed" 

# --- Analysis Functions ---

function plot_combined_evolution(config_name::String, detailed_file::String, metric_type::String, output_dir::String; skip_comparison=false)
    df = CSV.read(detailed_file, DataFrame)
    
    # Metric mapping
    col_5g = Symbol("Entries_5G")
    col_6g = Symbol("Entries_6G")
    
    if metric_type == "Fwd State Info Size (MB)"
        col_5g = Symbol("Memory_5G_MB")
        col_6g = Symbol("Memory_6G_MB")
    end
    
    # Calculate Totals per Time step
    total_5g = combine(groupby(df, :Time), col_5g => sum => :Total)
    total_6g = combine(groupby(df, :Time), col_6g => sum => :Total)
    
    generated_files = String[]

    # Comparison Plot (Log Scale)
    if !skip_comparison
        p_comp = plot(
            xlabel="Time (s)",
            ylabel="Total $metric_type (Log Scale)",
            title="Evolution of Total $metric_type\n$config_name",
            legend=:topleft,
            framestyle=:box,
            margin=10Plots.mm,
            yscale=:log10,
            size=(1200, 800),
            tickfontsize=12,
            guidefontsize=14,
            legendfontsize=12,
            titlefontsize=16
        )
        
        plot!(p_comp, total_5g.Time, total_5g.Total, label="5G (Total)", lw=4, color=:red)
        plot!(p_comp, total_6g.Time, total_6g.Total, label="6G-RUPA (Total)", lw=4, color=:blue)
        
        safe_config = replace(config_name, " " => "_")
        safe_metric = replace(metric_type, " " => "_", "(" => "", ")" => "")
        
        outfile_comp = joinpath(output_dir, "comparison_total_$(safe_metric)_$(safe_config).png")
        savefig(p_comp, outfile_comp)
        println("  -> Generated Comparison: $outfile_comp")
        push!(generated_files, basename(outfile_comp))
    end
    
    safe_config = replace(config_name, " " => "_")
    safe_metric = replace(metric_type, " " => "_", "(" => "", ")" => "")

    # Individual Plots (to showcase every UPF as requested)
    # 5G
    p_5g = plot(
        xlabel="Time (s)",
        ylabel="$metric_type",
        title="Evolution of $metric_type per UPF (5G)\n$config_name",
        legend=false,
        framestyle=:box,
        margin=10Plots.mm,
        size=(1200, 800),
        tickfontsize=12,
        guidefontsize=14,
        titlefontsize=16
    )
    
    upf_ids = unique(df.UPF_ID)
    for upf in upf_ids
        sub_df = filter(row -> row.UPF_ID == upf, df)
        plot!(p_5g, sub_df.Time, sub_df[!, col_5g], alpha=0.5, lw=2, label=nothing)
    end
    
    mean_5g = combine(groupby(df, :Time), col_5g => mean => :Mean)
    plot!(p_5g, mean_5g.Time, mean_5g.Mean, label="Mean", color=:black, lw=4, linestyle=:dash, legend=:topleft, legendfontsize=12)
    
    outfile_5g = joinpath(output_dir, "evolution_5g_$(safe_metric)_$(safe_config).png")
    savefig(p_5g, outfile_5g)
    push!(generated_files, basename(outfile_5g))
    
    # 6G
    p_6g = plot(
        xlabel="Time (s)",
        ylabel="$metric_type",
        title="Evolution of $metric_type per UPF (6G-RUPA)\n$config_name",
        legend=false,
        framestyle=:box,
        margin=10Plots.mm,
        size=(1200, 800),
        tickfontsize=12,
        guidefontsize=14,
        titlefontsize=16
    )
    
    for upf in upf_ids
        sub_df = filter(row -> row.UPF_ID == upf, df)
        plot!(p_6g, sub_df.Time, sub_df[!, col_6g], alpha=0.5, lw=2, label=nothing)
    end
    
    mean_6g = combine(groupby(df, :Time), col_6g => mean => :Mean)
    plot!(p_6g, mean_6g.Time, mean_6g.Mean, label="Mean", color=:black, lw=4, linestyle=:dash, legend=:topleft, legendfontsize=12)
    
    outfile_6g = joinpath(output_dir, "evolution_6grupa_$(safe_metric)_$(safe_config).png")
    savefig(p_6g, outfile_6g)
    push!(generated_files, basename(outfile_6g))
    
    return generated_files
end

function run_evolution_analysis(results_dir::String, images_dir::String)
    println("Running Evolution Analysis...")
    files = readdir(results_dir)
    
    # Find configurations that match our scenario filter
    configs = Set{String}()
    for f in files
        if startswith(f, "evolution_detailed_") && occursin(SCENARIO_FILTER, f)
            config = replace(f, "evolution_detailed_" => "")
            config = replace(config, ".csv" => "")
            push!(configs, config)
        end
    end
    
    println("Found configurations for $SCENARIO_NAME: $configs")
    
    generated_plots = String[]
    
    for config in configs
        # Data is already scaled in the simulation output, so we don't need to calculate or apply scale factor here.

        f_detailed = joinpath(results_dir, "evolution_detailed_$(config).csv")
        
        if isfile(f_detailed)
            # Entries
            plots = plot_combined_evolution(config, f_detailed, "Entries", images_dir, skip_comparison=true)
            append!(generated_plots, plots)
            
            # Memory
            plots = plot_combined_evolution(config, f_detailed, "Fwd State Info Size (MB)", images_dir, skip_comparison=true)
            append!(generated_plots, plots)
        end
    end
    return generated_plots
end

function plot_memory_reduction_factor(df::DataFrame, images_dir::String)
    println("Generating Memory Reduction Factor Plot...")
    
    grouped = combine(groupby(df, :Configuration), 
        :Total_5G_FwdStateInfoSize_MB => sum => :Total_5G,
        :Total_6GRUPA_FwdStateInfoSize_MB => sum => :Total_6G
    )
    
    grouped.Reduction_Factor = grouped.Total_5G ./ grouped.Total_6G
    
    p = bar(grouped.Configuration, grouped.Reduction_Factor,
        ylabel="Reduction Factor (5G / 6G-RUPA)",
        title="Memory Reduction Factor (Higher is Better)",
        legend=false,
        bar_width=0.6,
        xrotation=45,
        framestyle=:box,
        margin=20Plots.mm,
        color=:green,
        size=(1200, 800),
        tickfontsize=12,
        guidefontsize=14,
        titlefontsize=16
    )
    
    for (i, y) in enumerate(grouped.Reduction_Factor)
        annotate!(i, y, text(@sprintf("%.1fx", y), :bottom, 12))
    end
    
    outfile = joinpath(images_dir, "memory_reduction_factor.png")
    savefig(p, outfile)
    return basename(outfile)
end

function plot_table_sizes_boxplot(df::DataFrame, images_dir::String)
    println("Generating Box Plot of Table Sizes...")
    
    # Prepare data for plotting
    df_5g = select(df, :Operator, :Entries_5G => :Entries)
    df_5g.Architecture .= "5G"
    
    df_6g = select(df, :Operator, :Entries_6GRUPA => :Entries)
    df_6g.Architecture .= "6G-RUPA"
    
    long_df = vcat(df_5g, df_6g)
    
    p = groupedboxplot(long_df.Operator, long_df.Entries, group=long_df.Architecture,
        ylabel="Number of Entries (Log Scale)",
        title="Distribution of Forwarding Table Sizes",
        yscale=:log10,
        framestyle=:box,
        legend=:outertopright,
        margin=15Plots.mm,
        size=(1200, 800),
        tickfontsize=12,
        guidefontsize=14,
        legendfontsize=12,
        titlefontsize=16,
        bar_width=0.8,
        lw=2
    )
    
    outfile = joinpath(images_dir, "boxplot_table_sizes.png")
    savefig(p, outfile)
    return basename(outfile)
end

function plot_total_memory_comparison(df::DataFrame, images_dir::String)
    println("Generating Total Memory Comparison Plot...")
    
    grouped = combine(groupby(df, [:Operator, :Scenario]), 
        :Total_5G_FwdStateInfoSize_MB => sum => :Memory_5G,
        :Total_6GRUPA_FwdStateInfoSize_MB => sum => :Memory_6G
    )
    
    long_df = stack(grouped, [:Memory_5G, :Memory_6G], variable_name=:Metric, value_name=:Memory_MB)
    long_df.Label = long_df.Operator .* "\n" .* long_df.Scenario
    
    p = groupedbar(long_df.Label, long_df.Memory_MB, group=long_df.Metric,
        ylabel="Total Network Memory (MB)",
        title="Total Network Memory (Log Scale)",
        bar_width=0.8,
        lw=0,
        framestyle=:box,
        yscale=:log10,
        legend=:outertopright,
        margin=15Plots.mm,
        size=(1200, 800),
        tickfontsize=12,
        guidefontsize=14,
        legendfontsize=12,
        titlefontsize=16
    )
    
    outfile = joinpath(images_dir, "total_memory_comparison.png")
    savefig(p, outfile)
    return basename(outfile)
end

function plot_per_upf_statistics(df::DataFrame, images_dir::String)
    println("Generating Per-UPF Statistics Plots...")
    
    grouped = combine(groupby(df, [:Operator, :Scenario]), 
        :Total_5G_FwdStateInfoSize_MB => mean => :Avg_Mem_5G,
        :Total_5G_FwdStateInfoSize_MB => median => :Med_Mem_5G,
        :Total_5G_FwdStateInfoSize_MB => maximum => :Max_Mem_5G,
        :Total_5G_FwdStateInfoSize_MB => minimum => :Min_Mem_5G,
        
        :Total_6GRUPA_FwdStateInfoSize_MB => mean => :Avg_Mem_6G,
        :Total_6GRUPA_FwdStateInfoSize_MB => median => :Med_Mem_6G,
        :Total_6GRUPA_FwdStateInfoSize_MB => maximum => :Max_Mem_6G,
        :Total_6GRUPA_FwdStateInfoSize_MB => minimum => :Min_Mem_6G
    )

    plots = String[]

    function create_stat_plot(stat_name, col_suffix, title_suffix, filename)
        cols = [
            Symbol("$(col_suffix)_Mem_5G"), 
            Symbol("$(col_suffix)_Mem_6G")
        ]
        
        long_df = stack(grouped, cols, variable_name=:Metric, value_name=:Memory_MB)
        long_df.Label = long_df.Operator .* "\n" .* long_df.Scenario
        long_df.Metric = replace.(string.(long_df.Metric), "$(col_suffix)_" => "")
        
        p = groupedbar(long_df.Label, long_df.Memory_MB, group=long_df.Metric,
            ylabel="$stat_name Memory per UPF (MB)",
            title="$stat_name Memory per UPF (Log Scale)",
            bar_width=0.8,
            lw=0,
            framestyle=:box,
            yscale=:log10,
            legend=:outertopright,
            margin=15Plots.mm,
            size=(1200, 800),
            tickfontsize=12,
            guidefontsize=14,
            legendfontsize=12,
            titlefontsize=16
        )
        outfile = joinpath(images_dir, filename)
        savefig(p, outfile)
        return basename(outfile)
    end

    push!(plots, create_stat_plot("Average", "Avg", "Average", "average_memory_per_upf.png"))
    push!(plots, create_stat_plot("Median", "Med", "Median", "median_memory_per_upf.png"))
    push!(plots, create_stat_plot("Maximum", "Max", "Maximum", "max_memory_per_upf.png"))
    push!(plots, create_stat_plot("Minimum", "Min", "Minimum", "min_memory_per_upf.png"))
    
    return plots
end

function generate_report(df::DataFrame, evolution_plots::Vector{String}, static_plots::Vector{String}, images_dir::String)
    println("Generating Markdown Report...")
    # Save report in the images directory so it is self-contained
    report_path = joinpath(images_dir, "analysis_report.md")
    
    # Relative path to images from report (same directory)
    rel_img_path = "."

    open(report_path, "w") do io
        println(io, "# Single Tier Scenario Analysis (5G vs 6G-RUPA)")
        println(io, "")
        println(io, "Generated on: $(now())")
        println(io, "")
        
        println(io, "## 1. Executive Summary")
        println(io, "This report compares the forwarding information state for the Single Tier (Distributed) scenario.")
        println(io, "")
        
        # Summary Table
        println(io, "### Summary Statistics")
        println(io, "| Configuration | Total 5G State Size (MB) | Total 6G-RUPA State Size (MB) | Reduction Factor | Max 5G Entries | Max 6G-RUPA Entries |")
        println(io, "|---|---|---|---|---|---|")
        
        grouped = combine(groupby(df, :Configuration), 
            :Total_5G_FwdStateInfoSize_MB => sum => :Total_5G,
            :Total_6GRUPA_FwdStateInfoSize_MB => sum => :Total_6G,
            :Entries_5G => maximum => :Max_Entries_5G,
            :Entries_6GRUPA => maximum => :Max_Entries_6G
        )
        
        for row in eachrow(grouped)
            factor = row.Total_5G / row.Total_6G
            @printf(io, "| %s | %.2f | %.2f | **%.1fx** | %d | %d |\n", 
                row.Configuration, row.Total_5G, row.Total_6G, factor, row.Max_Entries_5G, row.Max_Entries_6G)
        end
        
        println(io, "")
        # println(io, "## 2. Memory Reduction Analysis")
        # println(io, "![Memory Reduction Factor]($rel_img_path/memory_reduction_factor.png)")
        # println(io, "")
        
        println(io, "## 2. Table Size Distribution (Box Plot)")
        println(io, "This plot shows the range of forwarding table sizes (number of entries) across all UPFs. A lower box means smaller tables, which is better for scalability. The log scale helps compare the massive difference between 5G and 6G-RUPA.")
        println(io, "![Box Plot of Table Sizes]($rel_img_path/boxplot_table_sizes.png)")
        println(io, "")
        
        println(io, "## 3. Detailed Memory Comparison")
        println(io, "### Total Network Memory")
        println(io, "This compares the total memory required to store forwarding state across the entire network. It highlights the overall efficiency gain of the 6G-RUPA architecture.")
        println(io, "![Total Memory Comparison]($rel_img_path/total_memory_comparison.png)")
        println(io, "")
        println(io, "### Average Memory per UPF")
        println(io, "This shows the average memory burden on a single UPF. Lower values mean individual network nodes can be lighter and more cost-effective.")
        println(io, "![Average Memory per UPF]($rel_img_path/average_memory_per_upf.png)")
        println(io, "")
        
        println(io, "## 4. Evolution Over Time")
        println(io, "These graphs track how the network state grows as users connect over time. 5G typically shows rapid linear growth, while 6G-RUPA remains stable due to its topological routing.")
        for plot_file in evolution_plots
            println(io, "### $plot_file")
            println(io, "![Evolution Plot]($rel_img_path/$plot_file)")
            println(io, "")
        end
    end
    println("Report generated: $report_path")
end

function main()
    set_default_plot_style()
    
    results_dir = get_results_dir()
    images_dir = get_images_dir(SCENARIO_NAME)
    
    println("Results Dir: $results_dir")
    println("Images Dir: $images_dir")
    
    # 1. Load Data
    all_data = load_raw_data()
    
    # 2. Filter for Single Tier (Distributed)
    # We look for "Distributed" in the Configuration name
    df = filter(row -> occursin(SCENARIO_FILTER, row.Configuration), all_data)
    
    if nrow(df) == 0
        println("No data found for scenario: $SCENARIO_FILTER")
        return
    end
    
    println("Loaded $(nrow(df)) rows for Single Tier scenario.")
    
    # 3. Run Analysis
    evolution_plots = run_evolution_analysis(results_dir, images_dir)
    
    static_plots = String[]
    # push!(static_plots, plot_memory_reduction_factor(df, images_dir))
    push!(static_plots, plot_table_sizes_boxplot(df, images_dir))
    push!(static_plots, plot_total_memory_comparison(df, images_dir))
    append!(static_plots, plot_per_upf_statistics(df, images_dir))
    
    # 4. Generate Report
    generate_report(df, evolution_plots, static_plots, images_dir)
    
    println("Single Tier Analysis Complete.")
end

main()
