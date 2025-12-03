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
    configs = Set{String}()
    for f in files
        if startswith(f, "evolution_5g_entries_")
            config = replace(f, "evolution_5g_entries_" => "")
            config = replace(config, ".csv" => "")
            push!(configs, config)
        end
    end
    
    all_data = DataFrame()
    
    for config in configs
        # Filename format: Operator_Scenario
        # Example: Vodafone_Centralized
        
        parts = split(config, " ")
        operator = length(parts) > 0 ? parts[1] : "Unknown"
        scenario = length(parts) > 1 ? join(parts[2:end], " ") : "Unknown"
        
        # Load the 4 evolution files
        f_5g_entries = joinpath(results_dir, "evolution_5g_entries_$(config).csv")
        f_5g_mb = joinpath(results_dir, "evolution_5g_fwd_state_info_size_mb_$(config).csv")
        f_6g_entries = joinpath(results_dir, "evolution_6grupa_entries_$(config).csv")
        f_6g_mb = joinpath(results_dir, "evolution_6grupa_fwd_state_info_size_mb_$(config).csv")
        
        if isfile(f_5g_entries) && isfile(f_5g_mb) && isfile(f_6g_entries) && isfile(f_6g_mb)
            df_5g_entries = CSV.read(f_5g_entries, DataFrame)
            df_5g_mb = CSV.read(f_5g_mb, DataFrame)
            df_6g_entries = CSV.read(f_6g_entries, DataFrame)
            df_6g_mb = CSV.read(f_6g_mb, DataFrame)
            cols = filter(n -> n != "Time", names(df_5g_entries))
            num_upfs = length(cols)
            # Extract values from last row
            vals_5g_entries = Vector(df_5g_entries[end, cols])
            vals_5g_mb = Vector(df_5g_mb[end, cols])
            vals_6g_entries = Vector(df_6g_entries[end, cols])
            vals_6g_mb = Vector(df_6g_mb[end, cols])
            # Construct the DataFrame
            df = DataFrame(
                UPF_ID = 1:num_upfs,
                Entries_5G = vals_5g_entries,
                Total_5G_FwdStateInfoSize_MB = vals_5g_mb,
                Entries_6GRUPA = vals_6g_entries,
                Total_6GRUPA_FwdStateInfoSize_MB = vals_6g_mb
            )
            df.Configuration .= config
            df.Operator .= operator
            df.Scenario .= scenario
            append!(all_data, df)
        end
    end
    return all_data
end

end
