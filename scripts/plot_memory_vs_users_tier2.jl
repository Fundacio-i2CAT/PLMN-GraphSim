using CSV
using DataFrames
using Plots
using Statistics
using Printf

# --- Configuration ---
RESULTS_DIR = joinpath(@__DIR__, "../results")
OUTPUT_DIR = joinpath(@__DIR__, "../docs/images/two_tier_scenario")

if !isdir(OUTPUT_DIR)
    mkpath(OUTPUT_DIR)
end

function plot_memory_vs_users(filename::String, scenario_name::String)
    filepath = joinpath(RESULTS_DIR, filename)
    if !isfile(filepath)
        println("File not found: $filepath")
        return
    end

    df = CSV.read(filepath, DataFrame)

    # Filter for Tier 2 UPFs
    df_tier2 = filter(row -> row.Tier == 2, df)

    if nrow(df_tier2) == 0
        println("No Tier 2 UPFs found in $filename")
        return
    end

    # We want to track the evolution of the bottleneck (Max Loaded UPF)
    # Group by Time and find the max memory/entries at each time step

    agg = combine(groupby(df_tier2, :Time),
        :Entries_5G => maximum => :Max_Entries_5G,
        :Memory_5G_MB => maximum => :Max_Memory_5G,
        :Entries_6G => maximum => :Max_Entries_6G,
        :Memory_6G_MB => maximum => :Max_Memory_6G
    )

    # Sort by Time just in case
    sort!(agg, :Time)

    # Plot Memory vs Users (Entries 5G)
    # X-axis: Max_Entries_5G
    # Y-axis: Memory (MB)

    p = plot(
        agg.Max_Entries_5G,
        agg.Max_Memory_5G,
        label="5G Architecture",
        xlabel="Number of Active Sessions (Users)",
        ylabel="Forwarding State Memory (MB)",
        title="Memory Usage vs. Scale (Tier 2 UPF) - $scenario_name",
        lw=3,
        color=:red,
        legend=:topleft,
        grid=true,
        formatter=:plain, # Avoid scientific notation if possible
        size=(1200, 800),
        dpi=300,
        left_margin=10Plots.mm,
        right_margin=4Plots.mm,
        bottom_margin=8Plots.mm,
        guidefont=font(12),
        tickfont=font(10),
        legendfont=font(10),
        titlefont=font(12)
    )

    plot!(
        p,
        agg.Max_Entries_5G,
        agg.Max_Memory_6G,
        label="6G-RUPA",
        lw=3,
        color=:blue
    )

    # Save plot
    output_filename = "memory_vs_users_$(replace(scenario_name, " " => "_")).png"
    savefig(p, joinpath(OUTPUT_DIR, output_filename))
    println("Generated plot: $output_filename")
end

# Generate for Verizon USA (Largest scenario)
plot_memory_vs_users("evolution_detailed_Verizon_USA_TwoTier.csv", "Verizon USA")

# Generate for Movistar Spain (Smaller scenario)
plot_memory_vs_users("evolution_detailed_Movistar_Spain_TwoTier.csv", "Movistar Spain")
