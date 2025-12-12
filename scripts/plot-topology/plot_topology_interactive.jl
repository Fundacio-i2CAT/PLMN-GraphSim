# Run this script from the project root:
# julia --project=. scripts/plot-topology/plot_topology_interactive.jl

using Pkg
Pkg.activate(joinpath(@__DIR__, "../.."))
using DesJulia6gRupa
using DesJulia6gRupa.DataLoading
using DesJulia6gRupa.Types
using DesJulia6gRupa.AgentGeneration
using TOML
using Plots
using Dates
using REPL.TerminalMenus
using Logging

# Set log level to Info to avoid too much debug noise during loading
global_logger(ConsoleLogger(stderr, Logging.Info))

function load_config()
    config_path = joinpath(@__DIR__, "../../config.toml")
    if !isfile(config_path)
        error("Config file not found at $config_path")
    end
    return TOML.parsefile(config_path)
end

function create_sim_config(toml_data)
    sim_data = toml_data["simulation"]
    return SimConfig(
        sim_data["min_sessions_per_user"],
        sim_data["max_sessions_per_user"],
        sim_data["scale_factor"],
        sim_data["duration"],
        get(sim_data, "mean_session_duration", 20.0),
        get(sim_data, "mean_offline_duration", 5.0),
        Symbol(get(sim_data, "scenario_mode", "single_tier")),
        get(sim_data, "num_centralized_upfs", 0),
        get(sim_data, "sampling_interval", 1.0)
    )
end

function get_valid_data_paths(data_dir::String, mccs::Vector{Int})
    # Try standard structure: data_dir/opencellid/mcc.csv
    csv_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
    
    # Fallback: data_dir/mcc.csv
    if !any(isfile, csv_paths)
         csv_paths_fallback = [joinpath(data_dir, "$(mcc).csv") for mcc in mccs]
         if any(isfile, csv_paths_fallback)
             return filter(isfile, csv_paths_fallback)
         end
    end
    
    valid_paths = filter(isfile, csv_paths)
    if isempty(valid_paths)
        @warn "No valid data files found for MCCs: $mccs in $data_dir"
    end
    return valid_paths
end

function main()
    config_data = load_config()
    sim_config = create_sim_config(config_data)
    
    countries_config = config_data["countries"]
    country_keys = collect(keys(countries_config))
    
    # 1. Select Country
    menu_countries = RadioMenu(country_keys, pagesize=10)
    choice_country = request("Select Country:", menu_countries)
    
    if choice_country == -1
        println("Cancelled.")
        return
    end
    
    selected_country_key = country_keys[choice_country]
    selected_country_config = countries_config[selected_country_key]
    
    println("Selected Country: $selected_country_key")
    
    # 2. Select Operator
    operators_config = selected_country_config["operators"]
    operator_keys = collect(keys(operators_config))
    menu_operators = RadioMenu(operator_keys, pagesize=10)
    choice_operator = request("Select Operator:", menu_operators)
    
    if choice_operator == -1
        println("Cancelled.")
        return
    end
    
    selected_operator_key = operator_keys[choice_operator]
    selected_operator_data = operators_config[selected_operator_key]
    operator_id = selected_operator_data["id"]
    
    println("Selected Operator: $selected_operator_key (ID: $operator_id)")
    
    # 3. Select Scenario (to determine num_upfs)
    scenarios = get(selected_country_config, "scenarios", Dict())
    if isempty(scenarios)
        println("No scenarios defined for this country.")
        return
    end
    
    scenario_names = collect(keys(scenarios))
    menu_scenarios = RadioMenu(scenario_names, pagesize=10)
    choice_scenario = request("Select Scenario:", menu_scenarios)
    
    if choice_scenario == -1
        println("Cancelled.")
        return
    end
    
    selected_scenario_name = scenario_names[choice_scenario]
    num_upfs = scenarios[selected_scenario_name]
    
    println("Selected Scenario: $selected_scenario_name (Num UPFs: $num_upfs)")
    
    # Load Topology
    data_dir = joinpath(@__DIR__, "../../", selected_country_config["data_dir"])
    mccs = Int[]
    if haskey(selected_country_config, "mccs")
        append!(mccs, selected_country_config["mccs"])
    elseif haskey(selected_country_config, "mcc")
        push!(mccs, selected_country_config["mcc"])
    end
    
    valid_paths = get_valid_data_paths(data_dir, mccs)
    if isempty(valid_paths)
        println("Error: No data files found.")
        return
    end
    
    println("Loading network topology... This may take a moment.")
    topology = load_and_deploy_network(valid_paths, operator_id, num_upfs, data_dir, sim_config)
    println("Topology loaded.")
    println("  gNBs: $(length(topology.gnb_locations))")
    println("  UPFs (Tier 1): $(length(topology.upf_locations))")
    if !isempty(topology.centralized_upf_locations)
        println("  UPFs (Tier 2): $(length(topology.centralized_upf_locations))")
    end
    
    # 4. Select Plot Type Loop
    plot_options = [
        "Plot gNBs",
        "Plot Agents",
        "Plot Agents and gNBs",
        "Plot Agents and gNBs and UPFs (Tier 1)",
        "Plot Agents and gNBs and UPFs (Tier 1 and Tier 2)",
        "Exit"
    ]
    
    menu_plot = RadioMenu(plot_options, pagesize=10)

    while true
        choice_plot = request("Select Plot Type:", menu_plot)
        
        if choice_plot == -1 || choice_plot == 6 # Exit
            println("Exiting.")
            break
        end
        
        # Prepare Data for Plotting
        gnb_lons = [p.lon for p in topology.gnb_locations]
        gnb_lats = [p.lat for p in topology.gnb_locations]
        
        upf_lons = [p.lon for p in topology.upf_locations]
        upf_lats = [p.lat for p in topology.upf_locations]
        
        central_upf_lons = [p.lon for p in topology.centralized_upf_locations]
        central_upf_lats = [p.lat for p in topology.centralized_upf_locations]
        
        # Generate Agents if needed
        agent_lons = Float64[]
        agent_lats = Float64[]
        
        if choice_plot in [2, 3, 4, 5]
            # Calculate number of agents to plot
            population = get(selected_country_config, "population", 0)
            mobile_adoption_rate = get(selected_country_config, "mobile_adoption_rate", 0.82)
            effective_population = population * mobile_adoption_rate
            
            # Use the scale factor from sim_config
            num_agents_to_plot = ceil(Int, effective_population / sim_config.scale_factor)
            
            println("Generating $num_agents_to_plot agents for visualization (Population: $population, Scale: $(sim_config.scale_factor))...")
            agent_locs = generate_agent_locations(topology, num_agents_to_plot)
            agent_lons = [p.lon for p in agent_locs]
            agent_lats = [p.lat for p in agent_locs]
        end
        
        # Determine limits based on country
        if selected_country_key == "usa"
            plot_ylims = (23, 50)
        else
            plot_ylims = (35, 44)
        end

        # Plotting
        p = plot(
            # title="Network Topology: $selected_country_key - $selected_operator_key", 
            xlabel="Longitude", 
            ylabel="Latitude", 
            legend=:bottomleft,
            size=(1200, 1200),
            dpi=300,
            aspect_ratio=:equal,
            ylims=plot_ylims
        )
        
        # Helper to add series
        function add_gnbs!()
            scatter!(p, gnb_lons, gnb_lats, label="gNBs", markersize=1.5, markercolor=:orange, markerstrokewidth=0, alpha=0.3)
        end
        
        function add_agents!()
            # Use smaller markers for high density
            ms = length(agent_lons) > 10000 ? 0.8 : 1.5
            scatter!(p, agent_lons, agent_lats, label="Agents", markersize=ms, markercolor=:blue, markerstrokewidth=0, alpha=0.6)
        end
        
        function add_upfs_tier1!()
            scatter!(p, upf_lons, upf_lats, label="UPFs (Tier 1)", markersize=7, markercolor=:red, shape=:square)
        end
        
        function add_upfs_tier2!()
            scatter!(p, central_upf_lons, central_upf_lats, label="UPFs (Tier 2)", markersize=12, markercolor=:purple, shape=:diamond)
        end
        
        if choice_plot == 1 # gNBs
            add_gnbs!()
        elseif choice_plot == 2 # Agents
            add_agents!()
        elseif choice_plot == 3 # Agents + gNBs
            add_agents!()
            add_gnbs!()
        elseif choice_plot == 4 # Agents + gNBs + UPFs T1
            add_agents!()
            add_gnbs!()
            add_upfs_tier1!()
        elseif choice_plot == 5 # Agents + gNBs + UPFs T1 + T2
            add_agents!()
            add_gnbs!()
            add_upfs_tier1!()
            add_upfs_tier2!()
        end
        
        display(p)
        println("Plot generated.")

        # Save the plot
        output_dir = joinpath(@__DIR__, "../../images/topology_plots")
        mkpath(output_dir)
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
        
        filename_pdf = "topology_$(selected_country_key)_$(selected_operator_key)_$(timestamp).pdf"
        output_path_pdf = joinpath(output_dir, filename_pdf)
        savefig(p, output_path_pdf)
        println("Plot saved to: $output_path_pdf")

        filename_png = "topology_$(selected_country_key)_$(selected_operator_key)_$(timestamp).png"
        output_path_png = joinpath(output_dir, filename_png)
        savefig(p, output_path_png)
        println("Plot saved to: $output_path_png")
        println("\n--- Ready for next plot ---\n")
    end
end

main()
