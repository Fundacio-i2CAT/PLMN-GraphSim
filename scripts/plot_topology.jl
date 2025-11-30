using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using DesJulia6gRupa
using DesJulia6gRupa.Plotting
using TOML

function plot_all_operators()
    # Load Configuration
    config_path = joinpath(@__DIR__, "../config.toml")
    if !isfile(config_path)
        error("Config file not found at $config_path")
    end
    
    toml_data = TOML.parsefile(config_path)
    countries = toml_data["countries"]
    scenarios = toml_data["scenarios"]

    # We'll just plot one scenario for brevity, or maybe the first one found?
    # Let's plot "Legacy Mobile" (Centralized) and "Edge" (Distributed) if they exist.
    
    target_scenarios = ["Legacy Mobile", "Edge"]

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
                            topology = DesJulia6gRupa.DataLoading.load_and_deploy_network(csv_path, op_id, num_upfs, data_dir)
                            plot_network_graph(topology, op_name, scenario_name)
                            
                            # Also generate the detailed agent/city plot
                            plot_operator_topology_with_cities(op_name, op_id, num_upfs, scenario_name; 
                                data_dir=data_dir, 
                                csv_path=csv_path
                            )
                            
                            println("    Plots generated.")
                        catch e
                            println("    Error plotting $op_name - $scenario_name: $e")
                            # Print stacktrace for debugging
                            # Base.showerror(stdout, e, catch_backtrace())
                        end
                    end
                end
            end
        end
    end
end

plot_all_operators()
