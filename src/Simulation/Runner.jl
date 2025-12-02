using ConcurrentSim
using ..DataLoading
using ..Types
using Logging

function run_operator_simulation(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String, config::SimConfig, data_dir::String, mccs::Vector{Int}, effective_population::Float64)
    @info "Running Simulation: $operator_name ($scenario_name)..."
    num_agents = ceil(Int, effective_population / config.scale_factor)
    
    csv_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
    # Check if at least one file exists
    valid_paths = filter(isfile, csv_paths)
    if isempty(valid_paths)
        error("No valid data files found for MCCs: $mccs in $data_dir")
    end
    topology = load_and_deploy_network(valid_paths, operator_id, num_upfs, data_dir)
    
    sim = ConcurrentSim.Simulation()
    global_state = init_global_state(topology, config)
    @process monitor_metrics(sim, global_state)
    for i in 1:num_agents
        @process user_lifecycle(sim, i, global_state, topology)
    end
    run(sim, config.duration) # Run for configured duration
    save_simulation_results(operator_name, scenario_name, global_state)
    save_raw_upf_data(operator_name, scenario_name, global_state, config.scale_factor)
end
