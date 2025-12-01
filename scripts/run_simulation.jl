using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.Types
using DesJulia6gRupa.LoggingSetup
using TOML
using Logging

function run_all_scenarios()
    # Load Configuration
    config_path = joinpath(@__DIR__, "../config.toml")
    if !isfile(config_path)
        error("Config file not found at $config_path")
    end

    toml_data = TOML.parsefile(config_path)

    # Setup Logger
    log_level = get(toml_data["simulation"], "log_level", "info")
    setup_logger(log_level)

    # Create SimConfig
    sim_config = SimConfig(
        toml_data["simulation"]["min_sessions_per_user"],
        toml_data["simulation"]["max_sessions_per_user"],
        toml_data["simulation"]["scale_factor"],
        toml_data["simulation"]["duration"],
        get(toml_data["simulation"], "mean_session_duration", 20.0),
        get(toml_data["simulation"], "mean_offline_duration", 5.0)
    )

    @info "Loaded Configuration from config.toml"
    @info "Scale Factor: $(sim_config.scale_factor)"
    @info "Duration: $(sim_config.duration)"

    # Run Scenarios
    countries = toml_data["countries"]

    for (country_key, country_config) in countries
        if !country_config["enabled"]
            continue
        end
        @info "  Processing Country: $country_key"
        scenarios = get(country_config, "scenarios", Dict())
        if isempty(scenarios)
            @warn "No scenarios defined for country: $country_key"
            continue
        end
        data_dir = joinpath(@__DIR__, "..", country_config["data_dir"])
        mccs = Int[]
        if haskey(country_config, "mccs")
            append!(mccs, country_config["mccs"])
        elseif haskey(country_config, "mcc")
            push!(mccs, country_config["mcc"])
        end
        for (scenario_name, num_upfs) in scenarios
            @info ">>> SCENARIO: $scenario_name ($num_upfs UPFs) <<<"

            operators = country_config["operators"]
            for (op_key, op_data) in operators
                if op_data["enabled"]
                    op_id = op_data["id"]
                    op_name = titlecase(op_key)
                    run_operator_simulation(op_name, op_id, num_upfs, scenario_name, sim_config, data_dir, mccs)
                end
            end
        end
    end
end

run_all_scenarios()
