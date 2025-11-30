using ConcurrentSim
using ..DataLoading
using ..Types

function run_operator_simulation(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String, config::SimConfig, data_dir::String, mccs::Vector{Int})
    println("\n==================================================")
    println("RUNNING SIMULATION: $operator_name ($scenario_name)")
    println("==================================================")
    num_agents = ceil(Int, EFFECTIVE_POPULATION / config.scale_factor)
    println("Configuration:")
    println("  Scale Factor: 1 Agent represents $(config.scale_factor) real people (Simulation uses $num_agents agents)")
    println("  Assumption: 1 Active UE per Agent")
    csv_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
    # Check if at least one file exists
    valid_paths = filter(isfile, csv_paths)
    if isempty(valid_paths)
        error("No valid data files found for MCCs: $mccs in $data_dir")
    end
    topology = load_and_deploy_network(valid_paths, operator_id, num_upfs, data_dir)
    println("Network Deployed:")
    println("  gNBs: $(length(topology.gnb_locations))")
    println("  UPFs: $(length(topology.upf_locations))")
    println("  Simulated Users: $num_agents")
    sim = ConcurrentSim.Simulation()
    global_state = init_global_state(topology, config)
    @process monitor_metrics(sim, global_state)
    for i in 1:num_agents
        @process user_lifecycle(sim, i, global_state, topology)
    end
    println("Starting Simulation...")
    run(sim, config.duration) # Run for configured duration
    println("Simulation Complete.")
    println("Final Total 5G State: $(last(global_state.history_total_5g_mb)) MB")
    println("Final Max UPF 5G State: $(last(global_state.history_max_upf_5g_mb)) MB")
    println("Final Total 6G-RUPA State: $(last(global_state.history_total_6g_mb)) MB")
    println("Final Max GUPF 6G-RUPA State: $(last(global_state.history_max_upf_6g_mb)) MB")

    # Calculate Scaled Impact
    # 5G State is per-UE, so we scale it up to represent the full population.
    real_world_total_5g_mb = last(global_state.history_total_5g_mb) * config.scale_factor
    real_world_max_upf_5g_mb = last(global_state.history_max_upf_5g_mb) * config.scale_factor

    # 6G State is per-gNB (Topology based). Since we use the REAL topology (all gNBs),
    # we do NOT scale this. It is already at real-world scale.
    real_world_total_6g_mb = last(global_state.history_total_6g_mb)
    real_world_max_upf_6g_mb = last(global_state.history_max_upf_6g_mb)

    println("\n--- Real World Extrapolation ($operator_name - $scenario_name) ---")
    println("Estimated Total 5G Network State: $(real_world_total_5g_mb / 1024) GB")
    println("Estimated Max UPF Load (Bottleneck): $(real_world_max_upf_5g_mb / 1024) GB")
    println("Estimated Total 6G-RUPA State: $(real_world_total_6g_mb) MB")
    println("Estimated Max GUPF Load (Bottleneck): $(real_world_max_upf_6g_mb) MB")
    print_forwarding_tables(global_state, config.scale_factor)
    save_simulation_results(operator_name, scenario_name, global_state)
    save_raw_upf_data(operator_name, scenario_name, global_state, config.scale_factor)
end
