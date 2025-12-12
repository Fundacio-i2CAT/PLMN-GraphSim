using Pkg
# Pkg.activate(joinpath(@__DIR__, ".."))

using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.Types
using DesJulia6gRupa.LoggingSetup
using TOML
using Logging
using DataFrames
using CSV
using Plots
using Statistics

function run_country_study(country_key, operator_key, operator_id, operator_name, num_edge_upfs, centralized_upf_counts, scale_factor_override)
    println("\n===================================================")
    println("Starting Study for $country_key ($operator_name)")
    println("===================================================")
    println("Edge UPFs: $num_edge_upfs")
    println("Centralized UPF Counts: $centralized_upf_counts")
    println("Scale Factor: $scale_factor_override")

    scenario_base_name = "TwoTier_Scaling"

    # Load base config
    config_path = joinpath(@__DIR__, "../../../config.toml")
    toml_data = TOML.parsefile(config_path)
    
    country_config = toml_data["countries"][country_key]
    data_dir = joinpath(@__DIR__, "../../..", country_config["data_dir"])
    mccs = Vector{Int}(country_config["mccs"])
    population = country_config["population"]
    mobile_adoption_rate = country_config["mobile_adoption_rate"]
    effective_population = population * mobile_adoption_rate
    
    # Base Sim Config
    sim_data = toml_data["simulation"]
    
    # Setup Logger
    setup_logger("info")

    results = DataFrame(Num_Centralized_UPFs = Int[], Avg_Memory_5G_MB = Float64[], Avg_Memory_6G_MB = Float64[])
    
    for num_centralized in centralized_upf_counts
        println("\n---------------------------------------------------")
        println("Running simulation with $num_centralized Centralized UPFs...")
        println("---------------------------------------------------")
        
        # Create Config with specific num_centralized_upfs
        sim_config = SimConfig(
            sim_data["min_sessions_per_user"],
            sim_data["max_sessions_per_user"],
            scale_factor_override, # Use override for faster study
            sim_data["duration"],
            get(sim_data, "mean_session_duration", 20.0),
            get(sim_data, "mean_offline_duration", 5.0),
            :two_tier, # Force two_tier scenario
            num_centralized,
            get(sim_data, "sampling_interval", 1.0)
        )
        
        scenario_name = "$(scenario_base_name)_$(num_centralized)"
        
        # Run Simulation
        try
            run_operator_simulation(operator_name, operator_id, num_edge_upfs, scenario_name, sim_config, data_dir, mccs, effective_population)
        catch e
            @error "Simulation failed for $num_centralized UPFs" exception=(e, catch_backtrace())
            continue
        end
        
        # Analyze Results
        safe_op = replace(operator_name, " " => "_")
        safe_scen = replace(scenario_name, " " => "_")
        results_file = joinpath(@__DIR__, "../../../results/evolution_detailed_$(safe_op)_$(safe_scen).csv")
        
        if !isfile(results_file)
            @error "Results file not found: $results_file"
            continue
        end

        df = CSV.read(results_file, DataFrame)
        
        # Filter for Tier 2 (Centralized) UPFs
        df_centralized = filter(row -> row.Tier == 2, df)
        
        if nrow(df_centralized) == 0
            @warn "No centralized UPF data found in results for $num_centralized UPFs"
            push!(results, (num_centralized, NaN, NaN))
            continue
        end
        
        # Calculate Average Memory
        avg_mem_5g = mean(df_centralized.Memory_5G_MB)
        avg_mem_6g = mean(df_centralized.Memory_6G_MB)
        
        println("  -> Avg Memory 5G: $(avg_mem_5g) MB")
        println("  -> Avg Memory 6G: $(avg_mem_6g) MB")
        
        push!(results, (num_centralized, avg_mem_5g, avg_mem_6g))
    end
    
    println("\n---------------------------------------------------")
    println("Study Complete for $country_key. Generating Plots...")
    println("---------------------------------------------------")
    
    # Ensure images directory exists
    images_dir = joinpath(@__DIR__, "../images/two_tier_scenario")
    if !isdir(images_dir)
        mkpath(images_dir)
    end

    # Plotting
    p = plot(
        results.Num_Centralized_UPFs, 
        [results.Avg_Memory_5G_MB results.Avg_Memory_6G_MB],
        label=["5G" "6G-RUPA"],
        color=["#E69F00" "#56B4E9"], # Orange for 5G, Sky Blue for 6G-RUPA
        xlabel="Number of Centralized UPFs",
        ylabel="Average Memory per UPF (MB)",
        # title="Impact of Centralized UPF Count on Memory ($country_key)",
        marker=:circle,
        lw=2,
        legend=:topright,
        framestyle=:box,
        dpi=300,
        yscale=:log10 # Log scale might be better if differences are huge
    )
    
    plot_path_pdf = joinpath(images_dir, "memory_vs_centralized_upfs_$(country_key).pdf")
    savefig(p, plot_path_pdf)
    println("Plot saved to: $plot_path_pdf")

    plot_path_png = joinpath(images_dir, "memory_vs_centralized_upfs_$(country_key).png")
    savefig(p, plot_path_png)
    println("Plot saved to: $plot_path_png")
    
    # Save aggregated results
    csv_path = joinpath(@__DIR__, "../../../results/memory_vs_centralized_upfs_$(country_key).csv")
    CSV.write(csv_path, results)
    println("Aggregated results saved to: $csv_path")
end

function run_all_studies()
    # Define configurations
    # We use a higher scale factor to keep the study quick, especially for USA
    studies = [
        (
            country="spain", 
            op_key="movistar", 
            op_id=7, 
            op_name="Movistar", 
            edge_upfs=52,
            counts=[1, 2, 4, 8, 16, 32],
            scale_factor=1000
        ),
        (
            country="usa", 
            op_key="verizon", 
            op_id=480, 
            op_name="Verizon", 
            edge_upfs=817,
            counts=[1, 2, 4, 8, 16, 32, 64], # Added 64 for USA
            scale_factor=1000 # Higher scale factor for USA to manage simulation time
        )
    ]

    for study in studies
        run_country_study(
            study.country, 
            study.op_key, 
            study.op_id, 
            study.op_name, 
            study.edge_upfs, 
            study.counts,
            study.scale_factor
        )
    end
end

run_all_studies()
