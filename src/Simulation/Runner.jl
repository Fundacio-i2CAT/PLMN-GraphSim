using ConcurrentSim
using ..DataLoading
using ..Types
using Logging

function get_valid_data_paths(data_dir::String, mccs::Vector{Int})
    csv_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
    valid_paths = filter(isfile, csv_paths)
    if isempty(valid_paths)
        error("No valid data files found for MCCs: $mccs in $data_dir")
    end
    return valid_paths
end

function run_operator_simulation(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String, config::SimConfig, data_dir::String, mccs::Vector{Int}, effective_population::Float64)
    @info "Running Simulation: $operator_name - ($scenario_name)..."
    number_of_agents = ceil(Int, effective_population / config.scale_factor)
    valid_paths = get_valid_data_paths(data_dir, mccs)
    topology = load_and_deploy_network(valid_paths, operator_id, num_upfs, data_dir, config)
    simulation = ConcurrentSim.Simulation()
    global_state = init_global_state_for_simulation(topology, config)
    @process monitor_metrics(simulation, global_state)
    for i in 1:number_of_agents
        @process user_lifecycle(simulation, i, global_state, topology)
    end
    run(simulation, config.duration) # Run for configured duration
    save_simulation_results(operator_name, scenario_name, global_state)
    save_raw_upf_data(operator_name, scenario_name, global_state, config.scale_factor)
end
