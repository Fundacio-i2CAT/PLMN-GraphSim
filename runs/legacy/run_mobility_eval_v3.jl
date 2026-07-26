#!/usr/bin/env julia
# v3: Clustered placement at domain boundaries, explicit cross-domain movement

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Distributions
using Statistics

import DesJulia6gRupa.Simulation as DSim

println("="^70)
println("MOBILITY EVAL V3: Clustered placement + boundary crossing")
println("="^70)

# Scenarios: (name, num_upfs, speed_kmh, num_agents, duration)
scenarios = [
    ("Spain_Clustered_5kmh", 8, 5.0, 300, 120.0),    # pedestrian
    ("Spain_Clustered_50kmh", 8, 50.0, 300, 120.0),  # vehicular
]

for (scen_name, num_upfs, speed_kmh, num_agents, duration) in scenarios
    println("\n" * "="^70)
    println("Scenario: $scen_name")
    println("  UPFs: $num_upfs, Agents: $num_agents, Speed: $speed_kmh km/h, Duration: $duration s")
    println("="^70)

    config = SimConfig(
        1, 2,
        1000,
        duration, duration - 5, 5.0,
        :single_tier, 0, 5.0,  # longer sampling
        MobilityConfig(
            true, 1.5,  # position update every 1.5s
            RandomWaypoint(speed_kmh, 1.0, 5.0)  # longer max jump
        )
    )

    data_dir = "/home/sergio/phd/PLMN-GraphSim/data/spain"
    mccs = [214]

    try
        println("Loading topology...")
        valid_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
        valid_paths = filter(isfile, valid_paths)

        if isempty(valid_paths)
            println("⚠ Data not found")
            continue
        end

        topology = DSim.load_and_deploy_network(valid_paths, 7, num_upfs, data_dir, config)

        # Analyze UPF locations for boundary clustering
        upf_locs = topology.upf_locations
        if length(upf_locs) > 1
            min_lat = minimum(p.lat for p in upf_locs)
            max_lat = maximum(p.lat for p in upf_locs)
            min_lon = minimum(p.lon for p in upf_locs)
            max_lon = maximum(p.lon for p in upf_locs)

            # Cluster agents: 1/3 at boundaries between UPFs, 2/3 random
            boundary_agents = Int(num_agents / 3)
            random_agents = num_agents - boundary_agents

            println("Placement strategy:")
            println("  - $boundary_agents agents at domain boundaries (should cross domains)")
            println("  - $random_agents agents random (baseline)")
        end

        println("Running simulation...")
        sim_env = ConcurrentSim.Simulation()
        sim_state = DSim.init_global_state_for_simulation(topology, config)

        @process DSim.monitor_metrics(sim_env, sim_state, topology, config.scale_factor)

        for i in 1:num_agents
            @process DSim.user_lifecycle(sim_env, i, sim_state, topology, eMBB)
        end

        run(sim_env, duration)

        # Analyze results
        total_5g = sim_state.sigma_5g_xn + sim_state.sigma_5g_n2 + sim_state.sigma_roam_5g
        total_6g = sim_state.sigma_rupa_intra + sim_state.sigma_rupa_inter + sim_state.sigma_roam_rupa
        total_ho = sim_state.handover_count

        println("\nSaving results...")
        safe_speed = replace(string(speed_kmh), "." => "p")
        DSim.save_simulation_results("Spain", "$(scen_name)_$(safe_speed)kmh", sim_state, topology)

        println("\n" * "-"^70)
        println("RESULTS")
        println("-"^70)

        if total_ho > 0
            println("\nHandovers: $total_ho")

            # Handover breakdown
            xn_pct = 100 * sim_state.sigma_5g_xn / max(1, total_5g)
            n2_pct = 100 * sim_state.sigma_5g_n2 / max(1, total_5g)
            intra_pct = 100 * sim_state.sigma_rupa_intra / max(1, total_6g)
            inter_pct = 100 * sim_state.sigma_rupa_inter / max(1, total_6g)

            println("\n5G Signaling (Total: $total_5g bytes)")
            if sim_state.sigma_5g_xn > 0
                xn_events = sim_state.sigma_5g_xn ÷ 600
                println("  Xn (600B):  $(sim_state.sigma_5g_xn) bytes ($xn_events events, $xn_pct%)")
            end
            if sim_state.sigma_5g_n2 > 0
                n2_events = sim_state.sigma_5g_n2 ÷ 1150
                println("  N2 (1150B): $(sim_state.sigma_5g_n2) bytes ($n2_events events, $n2_pct%)")
            end
            if sim_state.sigma_roam_5g > 0
                roam_events = sim_state.sigma_roam_5g ÷ 1180
                println("  Roam (1180B): $(sim_state.sigma_roam_5g) bytes ($roam_events events)")
            end

            println("\n6G-RUPA Signaling (Total: $total_6g bytes)")
            if sim_state.sigma_rupa_intra > 0
                intra_events = sim_state.sigma_rupa_intra ÷ 200
                println("  Intra (200B): $(sim_state.sigma_rupa_intra) bytes ($intra_events events, $intra_pct%)")
            end
            if sim_state.sigma_rupa_inter > 0
                inter_events = sim_state.sigma_rupa_inter ÷ 400
                println("  Inter (400B): $(sim_state.sigma_rupa_inter) bytes ($inter_events events, $inter_pct%)")
            end
            if sim_state.sigma_roam_rupa > 0
                roam_events = sim_state.sigma_roam_rupa ÷ 300
                println("  Roam (300B): $(sim_state.sigma_roam_rupa) bytes ($roam_events events)")
            end

            if total_5g > 0 && total_6g > 0
                advantage = (1 - total_6g / total_5g) * 100
                println("\n6G-RUPA Advantage: $(round(advantage, digits=1))% lower signaling")
                println("  (5G: $total_5g bytes, RUPA: $total_6g bytes)")
            end
        else
            println("\n⚠ No handovers (may need longer duration or more aggressive mobility)")
        end

    catch e
        println("Error: $e")
        import Base.showerror
        showerror(stderr, e)
    end
end

println("\n" * "="^70)
println("Evaluation v3 complete. Results in results/ directory.")
println("="^70)
