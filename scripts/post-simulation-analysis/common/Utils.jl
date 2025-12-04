module Utils

using CSV
using DataFrames
using Plots
using Statistics

export load_raw_data, parse_filename, set_default_plot_style, get_results_dir, get_images_dir

function set_default_plot_style()
    # Wong's Color Blind Friendly Palette
    cb_palette = [
        colorant"#E69F00", # Orange
        colorant"#56B4E9", # Sky Blue
        colorant"#009E73", # Bluish Green
        colorant"#F0E442", # Yellow
        colorant"#0072B2", # Blue
        colorant"#D55E00", # Vermilion
        colorant"#CC79A7", # Reddish Purple
        colorant"#000000"  # Black
    ]
    
    default(
        size=(800, 600), 
        guidefont=14, 
        tickfont=12, 
        legendfont=12,
        palette=cb_palette,
        linewidth=2
    )
end

function get_results_dir()
    # Assuming this file is in scripts/post-simulation-analysis/common/
    return joinpath(@__DIR__, "../../../results")
end

function get_images_dir(scenario_name::String)
    # Assuming this file is in scripts/post-simulation-analysis/common/
    path = joinpath(@__DIR__, "../../../images", scenario_name)
    if !isdir(path)
        mkpath(path)
    end
    return path
end

function parse_filename(filename::String)
    # Known prefixes for metrics
    prefixes = [
        ("evolution_5g_fwd_state_info_size_mb_", "5G Fwd State Info Size (MB)"),
        ("evolution_5g_entries_", "5G Entries"),
        ("evolution_6grupa_fwd_state_info_size_mb_", "6G Fwd State Info Size (MB)"),
        ("evolution_6grupa_entries_", "6G Entries")
    ]
    
    for (prefix, nice_name) in prefixes
        if startswith(filename, prefix)
            rest = replace(filename, prefix => "")
            rest = replace(rest, ".csv" => "")
            return prefix, nice_name, rest
        end
    end
    return nothing, nothing, nothing
end

function load_raw_data()
    results_dir = get_results_dir()
    files = readdir(results_dir)
    configs = Set{String}()
    
    prefix = "evolution_detailed_"
    for f in files
        if startswith(f, prefix)
            config = replace(f, prefix => "")
            config = replace(config, ".csv" => "")
            push!(configs, config)
        end
    end
    
    all_data = DataFrame()
    
    for config in configs
        # Filename format: Operator_Scenario
        # Example: Vodafone_Centralized
        
        parts = split(config, "_")
        operator = length(parts) > 0 ? parts[1] : "Unknown"
        scenario = length(parts) > 1 ? join(parts[2:end], "_") : "Unknown"
        
        f_path = joinpath(results_dir, "evolution_detailed_$(config).csv")
        
        if isfile(f_path)
            df = CSV.read(f_path, DataFrame)
            
            # Helper to get last values
            function get_last_values(df)
                max_time = maximum(df.Time)
                last_df = filter(row -> row.Time == max_time, df)
                return last_df
            end
            
            last_df = get_last_values(df)
            
            # Rename columns to match what analysis scripts expect
            rename!(last_df, :Memory_5G_MB => :Total_5G_FwdStateInfoSize_MB)
            rename!(last_df, :Entries_6G => :Entries_6GRUPA)
            rename!(last_df, :Memory_6G_MB => :Total_6GRUPA_FwdStateInfoSize_MB)
            
            last_df.Configuration .= config
            last_df.Operator .= operator
            last_df.Scenario .= scenario
            
            append!(all_data, last_df)
        end
    end
    return all_data
end

end
