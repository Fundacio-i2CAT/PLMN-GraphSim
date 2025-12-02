# How does the simulator actually work?

Once we have the data ready, the `Runner.jl` module takes care of initializing and running the simulation. Here's a high-level overview of how the simulator works:

```julia hl_lines="3 5 7 8 10 12" 
function run_operator_simulation(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String, config::SimConfig, data_dir::String, mccs::Vector{Int}, effective_population::Float64)
    @info "Running Simulation: $operator_name - ($scenario_name)..."
    number_of_agents = ceil(Int, effective_population / config.scale_factor) 
    valid_paths = get_valid_data_paths(data_dir, mccs)
    topology = load_and_deploy_network(valid_paths, operator_id, num_upfs, data_dir)
    simulation = ConcurrentSim.Simulation() 
    global_state = init_global_state(topology, config)
    @process monitor_metrics(simulation, global_state) # (1)
    for i in 1:number_of_agents
        @process user_lifecycle(simulation, i, global_state, topology) # (2)
    end
    run(simulation, config.duration) # (3)
    save_simulation_results(operator_name, scenario_name, global_state)
    save_raw_upf_data(operator_name, scenario_name, global_state, config.scale_factor)
end
```

1.  **Agent Calculation**: Determines the number of simulated users based on the real population and the configured `scale_factor`.
2.  **Network Deployment**: Loads the geographic data and deploys the 5G/6G network topology (gNBs, UPFs) for the specific operator.
3.  **Simulation Environment**: Initializes the `ConcurrentSim` discrete event simulation environment.
4.  **Metrics Monitoring**: Starts a background process that periodically records system metrics (latency, throughput, memory usage).
5.  **User Generation**: Spawns a lightweight process (green thread) for each user agent to simulate their lifecycle (movement, connection, data usage).
6.  **Execution**: Runs the simulation for the specified `duration` (in virtual time units).
7.  **Results**: Aggregates and saves the collected metrics to CSV files for analysis.
8.  

## The `@process`macro and the `ConcurrentSim` package

The `@process` macro is a key feature of the `ConcurrentSim` package, which enables the creation of lightweight concurrent processes (green threads) within the simulation environment. These processes can yield control back to the simulator, allowing for efficient time management and resource utilization.

When a process yields (e.g., waiting for an event like a UE connection), the simulator can switch to another process that is ready to run.

This cooperative multitasking approach allows thousands of user agents to be simulated concurrently very efficiently without the overhead of traditional operating system threads (and Julia handles this just automagically behind the scenes (1)
{.annotate}

1. Julia's coroutines (Tasks) are managed by the runtime, allowing efficient cooperative multitasking without manual thread management.