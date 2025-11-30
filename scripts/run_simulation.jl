using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.Types
using TOML

function run_all_scenarios()
    # Load Configuration
    config_path = joinpath(@__DIR__, "../config.toml")
    if !isfile(config_path)
        error("Config file not found at $config_path")
    end
    
    toml_data = TOML.parsefile(config_path)
    
    # Create SimConfig
    sim_config = SimConfig(
        toml_data["simulation"]["min_sessions_per_user"],
        toml_data["simulation"]["max_sessions_per_user"],
        toml_data["simulation"]["scale_factor"],
        toml_data["simulation"]["duration"]
    )

    println("Loaded Configuration from config.toml")
    println("Scale Factor: $(sim_config.scale_factor)")
    println("Duration: $(sim_config.duration)")

    # Operator Mapping (Name -> ID)
    operator_ids = Dict(
        "vodafone" => 1,
        "orange" => 3,
        "movistar" => 7
    )

    # Run Scenarios
    scenarios = toml_data["scenarios"]
    operators = toml_data["operators"]

    for (scenario_name, num_upfs) in scenarios
        println("\n>>> SCENARIO: $scenario_name ($num_upfs UPFs) <<<")
        
        for (op_key, enabled) in operators
            if enabled
                # Capitalize for display/file naming
                op_name = titlecase(op_key)
                if haskey(operator_ids, op_key)
                    op_id = operator_ids[op_key]
                    run_operator_simulation(op_name, op_id, num_upfs, scenario_name, sim_config)
                else
                    println("Warning: Unknown operator ID for $op_key")
                end
            end
        end
    end
end

run_all_scenarios()
