using CSV
using DataFrames
using Plots
using Statistics
using Printf

# Set default plot size and font
default(size=(1000, 600), guidefont=12, tickfont=10, legendfont=8)

function parse_filename(filename::String)
    # Known prefixes for metrics
    prefixes = [
        ("evolution_5g_mb_", "5G Memory (MB)"),
        ("evolution_5g_entries_", "5G Entries"),
        ("evolution_6g_mb_", "6G Memory (MB)"),
        ("evolution_6g_entries_", "6G Entries")
    ]
    
    for (prefix, nice_name) in prefixes
        if startswith(filename, prefix)
            # Extract the rest: Operator_Scenario.csv
            rest = replace(filename, prefix => "")
            rest = replace(rest, ".csv" => "")
            
            # We don't strictly need to split Operator and Scenario if we just use the full string as a label
            # But let's try to split by the last underscore if possible, or just use the whole thing
            # Assuming Scenario is the last part after the last underscore might be risky if Scenario has underscores.
            # Let's just use the full suffix as the "Configuration" name.
            return prefix, nice_name, rest
        end
    end
    return nothing, nothing, nothing
end

function plot_evolution_file(filepath::String, metric_name::String, config_name::String, output_dir::String)
    df = CSV.read(filepath, DataFrame)
    
    # Time column is "Time"
    time_col = df.Time
    
    # UPF columns are all other columns
    upf_cols = names(df, r"UPF_")
    
    if isempty(upf_cols)
        println("  Skipping $filepath: No UPF columns found.")
        return
    end
    
    # Create plot
    p = plot(
        xlabel="Time (s)",
        ylabel=metric_name,
        title="Evolution of $metric_name\n$config_name",
        legend=:outertopright,
        framestyle=:box,
        margin=5Plots.mm
    )
    
    # Plot each UPF
    for col in upf_cols
        plot!(p, time_col, df[!, col], label=col, alpha=0.6, lw=1.5)
    end
    
    # Calculate and plot Mean
    # Convert UPF columns to matrix
    upf_data = Matrix(df[:, upf_cols])
    mean_vals = mean(upf_data, dims=2)
    plot!(p, time_col, mean_vals, label="Mean", color=:black, lw=3, linestyle=:dash)
    
    # Save plot
    # Clean config name for filename
    safe_config = replace(config_name, " " => "_")
    safe_metric = replace(metric_name, " " => "_", "(" => "", ")" => "")
    outfile = joinpath(output_dir, "plot_$(safe_metric)_$(safe_config).png")
    
    savefig(p, outfile)
    println("  -> Generated: $outfile")
end

function main()
    results_dir = joinpath(@__DIR__, "../results")
    images_dir = joinpath(@__DIR__, "../images/evolution")
    
    if !isdir(results_dir)
        println("Results directory not found: $results_dir")
        return
    end
    
    if !isdir(images_dir)
        mkpath(images_dir)
    end
    
    files = readdir(results_dir)
    evolution_files = filter(f -> startswith(f, "evolution_") && endswith(f, ".csv"), files)
    
    if isempty(evolution_files)
        println("No evolution data files found in $results_dir")
        return
    end
    
    println("Found $(length(evolution_files)) evolution data files.")
    
    for file in evolution_files
        prefix, nice_name, config_name = parse_filename(file)
        
        if prefix !== nothing
            println("Processing $file...")
            plot_evolution_file(joinpath(results_dir, file), nice_name, config_name, images_dir)
        else
            println("Skipping unrecognized file format: $file")
        end
    end
    
    println("\nAll evolution plots generated in $images_dir")
end

main()
