using CSV
using DataFrames
using Plots
using Statistics
using Printf

# --- Configuration ---
RESULTS_DIR = joinpath(@__DIR__, "../results")
OUTPUT_DIR = joinpath(@__DIR__, "../docs/images/comparisons")

if !isdir(OUTPUT_DIR)
    mkpath(OUTPUT_DIR)
end

function get_scenario_from_filename(filename::String)
    # Filename format: evolution_detailed_<Operator>_<Country>_<Scenario>.csv
    parts = split(replace(filename, ".csv" => ""), "_")
    # parts[1] = evolution
    # parts[2] = detailed
    # parts[3] = Operator
    # parts[4] = Country
    # parts[5] = Scenario (Distributed / TwoTier)
    
    if length(parts) >= 5
        return (operator=parts[3], country=parts[4], scenario=parts[5])
    else
        return nothing
    end
end

function load_and_aggregate(filepath::String)
    df = CSV.read(filepath, DataFrame)
    
    # Aggregate by Time
    # We want Total Memory and Total Entries across all UPFs at each time step
    
    # Check column names
    # Based on previous read: Time, UPF_ID, Tier, Entries_5G, Memory_5G_MB, Entries_6G, Memory_6G_MB
    
    agg = combine(groupby(df, :Time), 
        :Memory_6G_MB => sum => :Total_Memory_6G,
        :Entries_6G => sum => :Total_Entries_6G,
        :Memory_5G_MB => sum => :Total_Memory_5G,
        :Entries_5G => sum => :Total_Entries_5G
    )
    return agg
end

function generate_comparison_plot(operator, country, file_distributed, file_twotier)
    println("Generating comparison for $operator - $country...")
    
    df_dist = load_and_aggregate(file_distributed)
    df_two = load_and_aggregate(file_twotier)
    
    # --- Plot 1: Total Memory 6G Evolution ---
    p1 = plot(
        title="Total Memory (6G-RUPA)",
        xlabel="Time (s)",
        ylabel="Memory (MB)",
        legend=:topleft
    )
    plot!(p1, df_dist.Time, df_dist.Total_Memory_6G, label="Distributed", lw=2)
    plot!(p1, df_two.Time, df_two.Total_Memory_6G, label="Two-Tier", lw=2)
    
    # --- Plot 2: Total Entries 6G Evolution ---
    p2 = plot(
        title="Total Entries (6G-RUPA)",
        xlabel="Time (s)",
        ylabel="Entries",
        legend=:topleft
    )
    plot!(p2, df_dist.Time, df_dist.Total_Entries_6G, label="Distributed", lw=2)
    plot!(p2, df_two.Time, df_two.Total_Entries_6G, label="Two-Tier", lw=2)

    # --- Plot 3: Memory Reduction Factor (5G vs 6G) ---
    # Let's compare the reduction factor between the two scenarios
    # Reduction = Memory 5G / Memory 6G
    
    red_dist = df_dist.Total_Memory_5G ./ df_dist.Total_Memory_6G
    red_two = df_two.Total_Memory_5G ./ df_two.Total_Memory_6G
    
    p3 = plot(
        title="Memory Reduction Factor (5G/6G)",
        xlabel="Time (s)",
        ylabel="Factor (x)",
        legend=:topleft
    )
    plot!(p3, df_dist.Time, red_dist, label="Distributed", lw=2)
    plot!(p3, df_two.Time, red_two, label="Two-Tier", lw=2)

    # --- Plot 4: Total Memory 5G (Baseline) ---
    # Just to show they are similar or different
    p4 = plot(
        title="Total Memory (5G Baseline)",
        xlabel="Time (s)",
        ylabel="Memory (MB)",
        legend=:topleft
    )
    plot!(p4, df_dist.Time, df_dist.Total_Memory_5G, label="Distributed", lw=2)
    plot!(p4, df_two.Time, df_two.Total_Memory_5G, label="Two-Tier", lw=2)

    # Combine into one figure
    final_plot = plot(p1, p2, p3, p4, layout=(2, 2), size=(1200, 800), margin=5Plots.mm)
    
    output_filename = "comparison_$(operator)_$(country).png"
    savefig(final_plot, joinpath(OUTPUT_DIR, output_filename))
    println("Saved $output_filename")
end

function main()
    files = readdir(RESULTS_DIR)
    
    # Group files by (Operator, Country)
    groups = Dict{Tuple{String, String}, Dict{String, String}}()
    
    for f in files
        if startswith(f, "evolution_detailed_") && endswith(f, ".csv")
            info = get_scenario_from_filename(f)
            if info !== nothing
                key = (info.operator, info.country)
                if !haskey(groups, key)
                    groups[key] = Dict{String, String}()
                end
                groups[key][info.scenario] = joinpath(RESULTS_DIR, f)
            end
        end
    end
    
    # Iterate groups and find pairs
    for ((op, country), scenarios) in groups
        if haskey(scenarios, "Distributed") && haskey(scenarios, "TwoTier")
            generate_comparison_plot(op, country, scenarios["Distributed"], scenarios["TwoTier"])
        else
            println("Skipping $op - $country: Incomplete pair (Found: $(keys(scenarios)))")
        end
    end
end

main()
