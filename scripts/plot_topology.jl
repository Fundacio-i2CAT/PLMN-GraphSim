using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using DesJulia6gRupa
using DesJulia6gRupa.Plotting
using DesJulia6gRupa.Types
using DesJulia6gRupa.AgentGeneration
using TOML
using CSV
using DataFrames

function plot_all_operators()
    # Load Configuration
    config_path = joinpath(@__DIR__, "../config.toml")
    if !isfile(config_path)
        error("Config file not found at $config_path")
    end
    
    toml_data = TOML.parsefile(config_path)
    countries = toml_data["countries"]
    scenarios = toml_data["scenarios"]
    
    # Get scale factor from config if available, else default
    sim_config = get(toml_data, "simulation", Dict())
    scale_factor = get(sim_config, "scale_factor", 1000)

    # Use all defined scenarios
    target_scenarios = keys(scenarios)

    for (country_key, country_config) in countries
        if !country_config["enabled"]
            continue
        end
        
        println("\n>>> PLOTTING COUNTRY: $country_key <<<")
        data_dir = joinpath(@__DIR__, "..", country_config["data_dir"])
        mcc = country_config["mcc"]
        operators = country_config["operators"]
        
        csv_path = joinpath(data_dir, "opencellid", "$(mcc).csv")
        if !isfile(csv_path)
            println("  Warning: Data file not found at $csv_path. Skipping.")
            continue
        end

        for (op_key, op_data) in operators
            if op_data["enabled"]
                op_id = op_data["id"]
                op_name = titlecase(op_key)
                
                println("  Operator: $op_name (ID: $op_id)")
                
                for scenario_name in target_scenarios
                    if haskey(scenarios, scenario_name)
                        num_upfs = scenarios[scenario_name]
                        println("    Scenario: $scenario_name ($num_upfs UPFs)")
                        
                        try
                            # 1. Load Topology
                            topology = DesJulia6gRupa.DataLoading.load_and_deploy_network(csv_path, op_id, num_upfs, data_dir)
                            
                            # 2. Generate Agents
                            total_pop = sum([m.population for m in topology.municipalities])
                            # Use constants from Types if available, or hardcode defaults
                            # Assuming Types exports these constants
                            ratio_under_15 = 0.15 # Default fallback
                            phone_adoption = 0.95 # Default fallback
                            try
                                ratio_under_15 = DesJulia6gRupa.Types.RATIO_UNDER_15
                                phone_adoption = DesJulia6gRupa.Types.PHONE_ADOPTION_OVER_15
                            catch
                                # Constants might not be exported or available
                            end
                            
                            eff_pop = total_pop * (1 - ratio_under_15) * phone_adoption
                            num_agents = ceil(Int, eff_pop / scale_factor)
                            
                            if num_agents > 100000
                                println("    Warning: Too many agents ($num_agents). Capping at 100,000 for plotting.")
                                num_agents = 100000
                            end
                            
                            println("    Generating $num_agents agents...")
                            agent_locs = generate_agent_locations(topology, num_agents)
                            
                            # 3. Load Cities
                            cities_csv = joinpath(data_dir, "cities.csv")
                            cities_list = Tuple{String, GeoPoint}[]
                            if isfile(cities_csv)
                                cities_df = CSV.read(cities_csv, DataFrame)
                                for row in eachrow(cities_df)
                                    push!(cities_list, (row.name, GeoPoint(row.lat, row.lon)))
                                end
                            end

                            # 4. Plot
                            plot_network_graph(topology, op_name, scenario_name)
                            
                            plot_topology_map(
                                topology, 
                                op_name, 
                                scenario_name; 
                                agent_locations=agent_locs,
                                cities=cities_list
                            )
                            
                            println("    Plots generated.")
                        catch e
                            println("    Error plotting $op_name - $scenario_name: $e")
                            # Print stacktrace for debugging
                            Base.showerror(stdout, e, catch_backtrace())
                        end
                    end
                end
            end
        end
    end
end

plot_all_operators()
