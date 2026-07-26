#!/usr/bin/env julia
# Mobility evaluation v2: tighter scenarios to trigger handovers

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Statistics

import DesJulia6gRupa.Simulation as DSim

# Scenarios: (name, num_upfs, speed_kmh, num_agents, duration)
# Reduced UPF count + more agents = more domain crossings
scenarios = [
    ("Spain_Tight_5kmh", 10, 5.0, 200, 60.0),    # pedestrian, longer
    ("Spain_Tight_50kmh", 10, 50.0, 200, 60.0),  # vehicular, longer
    ("USA_Tight_5kmh", 25, 5.0, 200, 60.0),      # pedestrian, USA scale
]

for (scen_name, num_upfs, speed_kmh, num_agents, duration) in scenarios
    println("\n" * "="^70)
    println("Scenario: $scen_name / $num_agents agents / $duration s")
    println("="^70)

    config = SimConfig(
        1, 2,
        1000,
        duration, duration - 1, 1.0,
        :single_tier, 0, 2.0,  # longer sampling interval
        MobilityConfig(
            true, 1.0,  # slower update for more position changes
            RandomWaypoint(speed_kmh, 0.0, 3.0)
        )
    )

    data_dir = "/home/sergio/phd/PLMN-GraphSim/data/spain"
    mccs = [214]

    try
        valid_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
        valid_paths = filter(isfile, valid_paths)

        if isempty(valid_paths)
            println("⚠ Data not found")
            continue
        end

        println("Loading topology ($num_upfs UPFs)...")
        topology = DSim.load_and_deploy_network(valid_paths, 7, num_upfs, data_dir, config)

        println("Running simulation ($num_agents agents, $(duration)s)...")
        sim_env = ConcurrentSim.Simulation()
        sim_state = DSim.init_global_state_for_simulation(topology, config)

        @process DSim.monitor_metrics(sim_env, sim_state, topology, config.scale_factor)

        for i in 1:num_agents
            @process DSim.user_lifecycle(sim_env, i, sim_state, topology, eMBB)
        end

        run(sim_env, duration)

        println("Saving results...")
        safe_speed = replace(string(speed_kmh), "." => "p")
        DSim.save_simulation_results("Spain", "$(scen_name)_$(safe_speed)kmh", sim_state, topology)

        # Report results
        total_sigma_5g = sim_state.sigma_5g_xn + sim_state.sigma_5g_n2 + sim_state.sigma_roam_5g
        total_sigma_6g = sim_state.sigma_rupa_intra + sim_state.sigma_rupa_inter + sim_state.sigma_roam_rupa
        total_handovers = sim_state.handover_count

        println("\nResults:")
        println("  Handovers: $total_handovers")
        if total_handovers > 0
            println("  Xn (600B):        $(sim_state.sigma_5g_xn) bytes ($(sim_state.sigma_5g_xn ÷ 600) events, $(round(100*sim_state.sigma_5g_xn/total_sigma_5g, digits=1))% of 5G)")
            println("  N2 (1150B):       $(sim_state.sigma_5g_n2) bytes ($(sim_state.sigma_5g_n2 ÷ 1150) events, $(round(100*sim_state.sigma_5g_n2/total_sigma_5g, digits=1))% of 5G)")
            println("  Roam 5G (1180B):  $(sim_state.sigma_roam_5g) bytes ($(sim_state.sigma_roam_5g ÷ 1180) events)")
            println("  5G Total:         $total_sigma_5g bytes")
            println("  ")
            println("  Intra (200B):     $(sim_state.sigma_rupa_intra) bytes ($(sim_state.sigma_rupa_intra ÷ 200) events, $(round(100*sim_state.sigma_rupa_intra/total_sigma_6g, digits=1))% of RUPA)")
            println("  Inter (400B):     $(sim_state.sigma_rupa_inter) bytes ($(sim_state.sigma_rupa_inter ÷ 400) events, $(round(100*sim_state.sigma_rupa_inter/total_sigma_6g, digits=1))% of RUPA)")
            println("  Roam RUPA (300B): $(sim_state.sigma_roam_rupa) bytes ($(sim_state.sigma_roam_rupa ÷ 300) events)")
            println("  6G-RUPA Total:    $total_sigma_6g bytes")
            if total_sigma_6g > 0
                reduction = (1 - total_sigma_6g / total_sigma_5g) * 100
                println("  6G-RUPA Advantage: $(round(reduction, digits=1))% lower signaling cost")
            end
        else
            println("  ⚠ No handovers (agents may not have moved enough)")
        end

    catch e
        println("Error: $e")
        import Base.showerror
        showerror(stderr, e)
    end
end

println("\n" * "="^70)
println("Evaluation complete.")
println("="^70)
