using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using DesJulia6gRupa
using DesJulia6gRupa.Plotting
using DesJulia6gRupa.Types
using DesJulia6gRupa.AgentGeneration
using TOML
using CSV
using DataFrames

function plot_single_scenario(op_name, op_id, scenario_name, num_upfs, valid_paths, data_dir, scale_factor)
    println("    Scenario: $scenario_name ($num_upfs UPFs)")

    try
        # 1. Load Topology
        topology = DesJulia6gRupa.DataLoading.load_and_deploy_network(valid_paths, op_id, num_upfs, data_dir)
        # 2. Generate Agents
        total_pop = sum([m.population for m in topology.municipalities])

        # Use constants from Types if available, or hardcode defaults
        ratio_under_15 = 0.15
        phone_adoption = 0.95
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
        cities_list = Tuple{String,GeoPoint}[]
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
        Base.showerror(stdout, e, catch_backtrace())
    end
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

function process_country(country_key, country_config, scale_factor)
    if !country_config["enabled"]
        return
    end
    println("\n>>> PLOTTING COUNTRY: $country_key <<<")

    scenarios = get(country_config, "scenarios", Dict())
    if isempty(scenarios)
        println("  Warning: No scenarios defined for country: $country_key")
        return
    end

    data_dir = joinpath(@__DIR__, "..", country_config["data_dir"])

    mccs = Int[]
    if haskey(country_config, "mccs")
        append!(mccs, country_config["mccs"])
    elseif haskey(country_config, "mcc")
        push!(mccs, country_config["mcc"])
    end

    csv_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
    valid_paths = filter(isfile, csv_paths)

    if isempty(valid_paths)
        println("  Warning: No data files found for MCCs $mccs in $data_dir. Skipping.")
        return
    end

    operators = country_config["operators"]
    for (op_key, op_data) in operators
        if op_data["enabled"]
            op_id = op_data["id"]
            op_name = titlecase(op_key)
            println("  Operator: $op_name (ID: $op_id)")

            for (scenario_name, num_upfs) in scenarios
                if !is_scenario_valid_for_country(scenario_name, country_key)
                    continue
                end

                plot_single_scenario(op_name, op_id, scenario_name, num_upfs, valid_paths, data_dir, scale_factor)
            end
        end
    end
end

function main()
    config_path = joinpath(@__DIR__, "../config.toml")
    if !isfile(config_path)
        error("Config file not found at $config_path")
    end
    toml_data = TOML.parsefile(config_path)
    countries = toml_data["countries"]
    sim_config = get(toml_data, "simulation", Dict())
    scale_factor = get(sim_config, "scale_factor", 1000)
    for (country_key, country_config) in countries
        process_country(country_key, country_config, scale_factor)
    end
end

main()
