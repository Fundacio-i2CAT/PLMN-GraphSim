using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.Types
using DesJulia6gRupa.LoggingSetup
using TOML
using Logging

function load_config()
    config_path = joinpath(@__DIR__, "../config.toml")
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
        # Default to basic single-tier scenario if not specified
        Symbol(get(sim_data, "scenario_mode", "single_tier")),
        get(sim_data, "num_centralized_upfs", 0),
        get(sim_data, "sampling_interval", 1.0)
    )
end

function is_scenario_valid_for_country(scenario_name, country_key)
    if occursin("Spain", scenario_name) && country_key != "spain"
        return false
    end
    if occursin("USA", scenario_name) && country_key != "usa"
        return false
    end
    return true
end

function process_country(country_key, country_config, sim_config)
    if !country_config["enabled"]
        return
    end
    @info "  Processing Country: $country_key"
    scenarios = get(country_config, "scenarios", Dict())
    if isempty(scenarios)
        @warn "No scenarios defined for country: $country_key"
        return
    end
    
    data_dir = joinpath(@__DIR__, "..", country_config["data_dir"])
    mccs = Int[]
    if haskey(country_config, "mccs")
        append!(mccs, country_config["mccs"])
    elseif haskey(country_config, "mcc")
        push!(mccs, country_config["mcc"])
    end
    population = get(country_config, "population", 0)
    mobile_adoption_rate = get(country_config, "mobile_adoption_rate", 0.82)
    effective_population = population * mobile_adoption_rate
    for (scenario_name, num_upfs) in scenarios
        if !is_scenario_valid_for_country(scenario_name, country_key)
            continue
        end
        @info ">>> SCENARIO: $scenario_name ($num_upfs UPFs) <<<"
        operators = country_config["operators"]
        for (op_key, op_data) in operators
            if op_data["enabled"]
                op_id = op_data["id"]
                op_name = titlecase(op_key)
                try
                    run_operator_simulation(op_name, op_id, num_upfs, scenario_name, sim_config, data_dir, mccs, effective_population)
                catch e
                    @error "Simulation failed for Operator: $op_name ($op_id) in Scenario: $scenario_name" exception=(e, catch_backtrace())
                end
            end
        end
    end
end

function run_all_scenarios()
    toml_data = load_config()
    log_level = get(toml_data["simulation"], "log_level", "info")
    setup_logger(log_level)
    sim_config = create_sim_config(toml_data)
    @info "Loaded Configuration from config.toml"
    @info "Scale Factor: $(sim_config.scale_factor)"
    @info "Duration: $(sim_config.duration)"
    countries = toml_data["countries"]
    for (country_key, country_config) in countries
        process_country(country_key, country_config, sim_config)
    end
end

run_all_scenarios()
