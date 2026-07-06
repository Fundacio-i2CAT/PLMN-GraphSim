#!/usr/bin/env julia
# Mobility evaluation: collect σ distributions on Spain/USA topologies

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Statistics

import DesJulia6gRupa.Simulation as DSim

# Test scenarios: (operator_id, scenario_name, num_upfs, speed_kmh, num_agents, duration)
scenarios = [
    ("Spain", 7, "Spain Distributed", 52, 5.0, 50, 20.0),    # pedestrian, quick test
    ("Spain", 7, "Spain Distributed", 52, 50.0, 50, 20.0),   # vehicular
    ("USA", 480, "USA Distributed", 817, 5.0, 50, 20.0),     # pedestrian
]

for (country, op_id, scen_name, num_upfs, speed_kmh, num_agents, duration) in scenarios
    println("\n" * "="^70)
    println("Scenario: $country / $scen_name / $speed_kmh km/h / $num_agents agents")
    println("="^70)

    # Config
    config = SimConfig(
        1, 2,           # min/max sessions
        1000,           # scale factor
        duration, duration - 1, 1.0,  # duration, mean_session, mean_offline
        :single_tier, 0, 1.0,  # scenario, num_centralized, sampling
        MobilityConfig(
            true, 0.5,  # enabled, update_interval
            RandomWaypoint(speed_kmh, 0.0, 2.0)  # speed, pause_time, max_jump_km
        )
    )

    # Data paths
    if country == "Spain"
        data_dir = "/home/sergio/phd/PLMN-GraphSim/data/spain"
        mccs = [214]
        population = 49_442_844
    else  # USA
        data_dir = "/home/sergio/phd/PLMN-GraphSim/data/usa"
        mccs = [310, 311, 312]  # subset for speed
        population = 100_000_000  # scaled for subset
    end

    # Load topology
    try
        valid_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
        valid_paths = filter(isfile, valid_paths)

        if isempty(valid_paths)
            println("⚠ Data not found for $country MCCs $mccs; skipping")
            continue
        end

        topology = DSim.load_and_deploy_network(valid_paths, op_id, num_upfs, data_dir, config)

        # Run simulation
        sim_env = ConcurrentSim.Simulation()
        sim_state = DSim.init_global_state_for_simulation(topology, config)

        @process DSim.monitor_metrics(sim_env, sim_state, topology, config.scale_factor)

        for i in 1:num_agents
            @process DSim.user_lifecycle(sim_env, i, sim_state, topology, eMBB)
        end

        run(sim_env, duration)

        # Save results
        safe_speed = replace(string(speed_kmh), "." => "p")
        DSim.save_simulation_results(country, "$(scen_name)_$(safe_speed)kmh", sim_state, topology)

        # Report σ totals
        total_sigma_5g = sim_state.sigma_5g_xn + sim_state.sigma_5g_n2 + sim_state.sigma_roam_5g
        total_sigma_6g = sim_state.sigma_rupa_intra + sim_state.sigma_rupa_inter + sim_state.sigma_roam_rupa
        total_handovers = sim_state.handover_count

        println("\nResults:")
        println("  Handovers: $total_handovers")
        println("  Xn (600B):        $(sim_state.sigma_5g_xn) bytes ($(sim_state.sigma_5g_xn ÷ 600) events)")
        println("  N2 (1150B):       $(sim_state.sigma_5g_n2) bytes ($(sim_state.sigma_5g_n2 ÷ 1150) events)")
        println("  Roam 5G (1180B):  $(sim_state.sigma_roam_5g) bytes ($(sim_state.sigma_roam_5g ÷ 1180) events)")
        println("  5G Total:         $total_sigma_5g bytes")
        println("  ")
        println("  Intra (200B):     $(sim_state.sigma_rupa_intra) bytes ($(sim_state.sigma_rupa_intra ÷ 200) events)")
        println("  Inter (400B):     $(sim_state.sigma_rupa_inter) bytes ($(sim_state.sigma_rupa_inter ÷ 400) events)")
        println("  Roam RUPA (300B): $(sim_state.sigma_roam_rupa) bytes ($(sim_state.sigma_roam_rupa ÷ 300) events)")
        println("  6G-RUPA Total:    $total_sigma_6g bytes")
        println("  ")
        if total_sigma_5g > 0 && total_sigma_6g > 0
            reduction = (1 - total_sigma_6g / total_sigma_5g) * 100
            println("  6G-RUPA Reduction: $(round(reduction, digits=1))%")
        end

    catch e
        println("Error running scenario: $e")
        continue
    end
end

println("\n" * "="^70)
println("Mobility evaluation complete. Results saved to results/")
println("="^70)
