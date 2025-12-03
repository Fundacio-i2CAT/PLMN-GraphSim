module Utils

using CSV
using DataFrames
using Plots
using Statistics

export load_raw_data, parse_filename, set_default_plot_style, get_results_dir, get_images_dir

function set_default_plot_style()
    default(size=(800, 600), guidefont=12, tickfont=10, legendfont=10)
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
    raw_files = filter(f -> startswith(f, "raw_upf_state_") && endswith(f, ".csv"), files)
    
    all_data = DataFrame()
    
    for file in raw_files
        # Filename format: raw_upf_state_Operator_Scenario.csv
        # Example: raw_upf_state_Vodafone_Centralized.csv
        # We want to filter for specific scenarios later, but for now load everything
        
        # Extract configuration name
        rest = replace(file, "raw_upf_state_" => "")
        rest = replace(rest, ".csv" => "")
        
        # Try to parse Operator and Scenario if possible, but fallback to full string
        parts = split(rest, " ")
        operator = length(parts) > 0 ? parts[1] : "Unknown"
        scenario = length(parts) > 1 ? join(parts[2:end], " ") : "Unknown"
        
        df = CSV.read(joinpath(results_dir, file), DataFrame)
        df.Configuration .= rest
        df.Operator .= operator
        df.Scenario .= scenario
        
        append!(all_data, df)
    end
    
    return all_data
end

end
