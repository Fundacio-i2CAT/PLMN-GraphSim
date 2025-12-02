# How does the simulator actually work?

## Running the Simulation

Once we have the data ready, the `Runner.jl` module takes care of initializing and running the simulation. Here's the piece of code that starts the simulation:

```julia hl_lines="3 5 7 8 10 12" 
function run_operator_simulation(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String, config::SimConfig, data_dir::String, mccs::Vector{Int}, effective_population::Float64)
    @info "Running Simulation: $operator_name - ($scenario_name)..."
    number_of_agents = ceil(Int, effective_population / config.scale_factor) 
    valid_paths = get_valid_data_paths(data_dir, mccs)
    topology = load_and_deploy_network(valid_paths, operator_id, num_upfs, data_dir)
    simulation = ConcurrentSim.Simulation() 
    global_state = init_global_state_for_simulation(topology, config)
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


So essentially we are initializing the simulation environment, creating a process for each user agent, and running the simulation while monitoring key metrics.

??? note "The `@process` macro"

    The `@process` macro is a key feature of the `ConcurrentSim` package, which enables the creation of lightweight concurrent processes (green threads) within the simulation environment. These processes can yield control back to the simulator, allowing for efficient time management and resource utilization.

    When a process yields (e.g., waiting for an event like a UE connection), the simulator can switch to another process that is ready to run.

    This cooperative multitasking approach allows thousands of user agents to be simulated concurrently very efficiently without the overhead of traditional operating system threads (and Julia handles this just automagically behind the scenes (1)
    {.annotate}

    1. Julia's coroutines (Tasks) are managed by the runtime, allowing efficient cooperative multitasking without manual thread management.

## The User Lifecycle Process

The simulation basically occurs inside the `user_lifecycle` process for each user agent:

```julia hl_lines="8-10"
function run_operator_simulation(operator_name::String, operator_id::Int, num_upfs::Int, scenario_name::String, config::SimConfig, data_dir::String, mccs::Vector{Int}, effective_population::Float64)
    @info "Running Simulation: $operator_name - ($scenario_name)..."
    number_of_agents = ceil(Int, effective_population / config.scale_factor) 
    valid_paths = get_valid_data_paths(data_dir, mccs)
    topology = load_and_deploy_network(valid_paths, operator_id, num_upfs, data_dir)
    simulation = ConcurrentSim.Simulation() 
    global_state = init_global_state_for_simulation(topology, config)
    @process monitor_metrics(simulation, global_state) # (1)
    for i in 1:number_of_agents
        @process user_lifecycle(simulation, i, global_state, topology) # (2)
    end
    run(simulation, config.duration) # (3)
    save_simulation_results(operator_name, scenario_name, global_state)
    save_raw_upf_data(operator_name, scenario_name, global_state, config.scale_factor)
end
```

The user lifecycle process simulates the behavior of a single user over time. Function is more or less self-explanatory

```julia hl_lines="3-22"
@resumable function user_lifecycle(env, user_id, sim_state, topology::NetworkTopology)
    @yield await_user_offline(env, sim_state) # Random start delay to avoid thundering herd at t=0
    while true
        if is_simulation_time_over(env, sim_state)
            break
        end
        agent_location = select_agent_location(topology)
        gnb_index = find_serving_gnb(topology, agent_location)
        if gnb_index != 0
            assigned_upf_index = connect_agent_to_gnb_and_upf(env, topology, user_id, agent_location, gnb_index)
            num_sessions = create_random_ue_connections(sim_state, assigned_upf_index)
            session_duration = rand(Exponential(sim_state.config.mean_session_duration))
            @yield timeout(env, session_duration)
            release_ue_connections(sim_state, assigned_upf_index, num_sessions)
            @debug "User $user_id disconnected from gNB $gnb_index at time $(now(env))"
            disconnect_ue_from_gnb_and_upf(topology, user_id, gnb_index)
        end
        @yield await_user_offline(env, sim_state) # Offline / Inter-session wait
    end
end
```

??? note "The `@resumable` macro"

    The `@resumable` macro is used to define a process that can yield control back to the simulation environment. This allows the process to pause its execution at certain points (e.g., waiting for a timeout or an event) and resume later, enabling efficient multitasking within the simulation.

??? note "The `@yield` macro"

    The `@yield` macro is used to let the simulation environment know that the current process is yielding control back to the simulator. This allows other processes to run while the current process is waiting for an event or a timeout.

