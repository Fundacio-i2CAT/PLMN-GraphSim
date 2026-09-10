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

const ANALYZE_ONLY = "--analyze-only" in ARGS
# Replot the combined figure from the cached per-operator CSVs, skipping the sweeps.
const COMBINED_ONLY = "--combined-only" in ARGS
const IMAGES_DIR = get(ENV, "PLMN_GRAPHICS_DIR",
                       joinpath(@__DIR__, "../../../images/two_tier_scenario"))

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

    results = DataFrame(Num_Centralized_UPFs = Int[], Avg_Memory_5G_MB = Float64[], Avg_Memory_6G_MB = Float64[], Max_Memory_5G_MB = Float64[], Max_Memory_6G_MB = Float64[])
    
    for num_centralized in centralized_upf_counts
        println("\n---------------------------------------------------")
        action = ANALYZE_ONLY ? "Analyzing results for" : "Running simulation with"
        println("$action $num_centralized Centralized UPFs...")
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
        
        if !ANALYZE_ONLY
            try
                seed = 20260902 + 100 * operator_id + num_centralized
                run_operator_simulation(operator_name, operator_id, num_edge_upfs, scenario_name, sim_config, data_dir, mccs, effective_population; seed)
            catch e
                @error "Simulation failed for $num_centralized UPFs" exception=(e, catch_backtrace())
                continue
            end
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
        
        # Compare the completed deployment, not the temporal mean of its ramp-up.
        final_time = maximum(df.Time)
        df_centralized = filter(row -> row.Tier == 2 && row.Time == final_time, df)
        
        if nrow(df_centralized) == 0
            @warn "No centralized UPF data found in results for $num_centralized UPFs"
            push!(results, (num_centralized, NaN, NaN, NaN, NaN))
            continue
        end
        
        # Calculate Average Memory
        avg_mem_5g = mean(df_centralized.Memory_5G_MB)
        avg_mem_6g = mean(df_centralized.Memory_6G_MB)
        max_mem_5g = maximum(df_centralized.Memory_5G_MB)
        max_mem_6g = maximum(df_centralized.Memory_6G_MB)
        
        println("  -> Avg Memory 5G: $(avg_mem_5g) MB")
        println("  -> Avg Memory 6G: $(avg_mem_6g) MB")
        
        push!(results, (num_centralized, avg_mem_5g, avg_mem_6g, max_mem_5g, max_mem_6g))
    end
    
    println("\n---------------------------------------------------")
    println("Study Complete for $country_key. Generating Plots...")
    println("---------------------------------------------------")
    
    # Ensure images directory exists
    images_dir = IMAGES_DIR
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
        ylabel="Final memory per UPF (MiB)",
        # title="Impact of Centralized UPF Count on Memory ($country_key)",
        marker=:circle,
        lw=2,
        legend=:topright,
        framestyle=:box,
        dpi=300,
        yscale=:log10 # Log scale might be better if differences are huge
    )
    
    plot_path_pdf = joinpath(images_dir, "memory_vs_centralized_upfs_$(country_key)_$(operator_key).pdf")
    savefig(p, plot_path_pdf)
    println("Plot saved to: $plot_path_pdf")

    plot_path_png = joinpath(images_dir, "memory_vs_centralized_upfs_$(country_key)_$(operator_key).png")
    savefig(p, plot_path_png)
    println("Plot saved to: $plot_path_png")
    
    # Save aggregated results
    csv_path = joinpath(@__DIR__, "../../../results/memory_vs_centralized_upfs_$(country_key)_$(operator_key).csv")
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
            country="spain", 
            op_key="orange", 
            op_id=3, 
            op_name="Orange", 
            edge_upfs=52,
            counts=[1, 2, 4, 8, 16, 32],
            scale_factor=1000
        ),
        (
            country="spain", 
            op_key="vodafone", 
            op_id=1, 
            op_name="Vodafone", 
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
            counts=[1, 2, 4, 8, 16, 32, 64],
            scale_factor=1000
        ),
        (
            country="usa", 
            op_key="att", 
            op_id=410, 
            op_name="Att", 
            edge_upfs=817,
            counts=[1, 2, 4, 8, 16, 32, 64],
            scale_factor=1000
        ),
        (
            country="usa", 
            op_key="tmobile", 
            op_id=260, 
            op_name="Tmobile", 
            edge_upfs=817,
            counts=[1, 2, 4, 8, 16, 32, 64],
            scale_factor=1000
        )
    ]

    for study in studies
        COMBINED_ONLY && break
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

    # Generate Combined Plot
    generate_combined_plot(studies)
end

function generate_combined_plot(studies)
    println("\n---------------------------------------------------")
    println("Generating Combined Plot...")
    println("---------------------------------------------------")
    
    p = plot(
        xlabel="Number of Centralized UPFs",
        ylabel="Final memory per UPF (MiB)",
        yscale=:log10,
        legend=:right,
        legendfontsize=10,
        framestyle=:box,
        dpi=300,
        # Sized for a single IEEE Access column: the canvas is kept small so the
        # fonts stay legible after the ~3x downscale to \columnwidth.
        size=(660, 520),
        left_margin=4Plots.mm,
        right_margin=4Plots.mm,
        bottom_margin=4Plots.mm,
        guidefont=font(13),
        tickfont=font(11)
    )

    colors = [:blue, :red, :green, :orange, :purple, :cyan]
    markers = [:circle, :square, :diamond, :utriangle, :dtriangle, :star5]

    for (i, study) in enumerate(studies)
        study.op_key in ("movistar", "verizon") || continue
        csv_path = joinpath(@__DIR__, "../../../results/memory_vs_centralized_upfs_$(study.country)_$(study.op_key).csv")
        if !isfile(csv_path)
            println("  Warning: Results file not found for $(study.op_name) ($csv_path)")
            continue
        end
        
        df = CSV.read(csv_path, DataFrame)
        
        # Plot 5G (Dashed)
        plot!(p, df.Num_Centralized_UPFs, df.Avg_Memory_5G_MB, 
            label="$(study.op_name) (5G)", 
            color=colors[i], 
            linestyle=:dash,
            marker=markers[i],
            alpha=0.5
        )
        
        # Plot 6G (Solid)
        plot!(p, df.Num_Centralized_UPFs, df.Avg_Memory_6G_MB, 
            label="$(study.op_name) (6G-RUPA)", 
            color=colors[i], 
            linestyle=:solid,
            marker=markers[i],
            lw=2
        )
    end
    
    images_dir = IMAGES_DIR
    plot_path_pdf = joinpath(images_dir, "memory_vs_centralized_upfs_combined.pdf")
    savefig(p, plot_path_pdf)
    println("Combined Plot saved to: $plot_path_pdf")

    plot_path_png = joinpath(images_dir, "memory_vs_centralized_upfs_combined.png")
    savefig(p, plot_path_png)
    println("Combined Plot saved to: $plot_path_png")
end

run_all_studies()
