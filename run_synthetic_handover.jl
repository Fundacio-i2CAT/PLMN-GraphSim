#!/usr/bin/env julia
# Synthetic handover scenario: 3 UPFs, 6 gNBs, controlled agent movement to force handovers

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Graphs
using MetaGraphsNext

import DesJulia6gRupa.Simulation as DSim

println("="^70)
println("SYNTHETIC HANDOVER SCENARIO: 3 UPFs, 6 gNBs, forced movement")
println("="^70)

# Synthetic topology: 3 UPFs in a line, 2 gNBs per UPF
# UPF 1: gNB 1-2 (cluster at lat 40.0)
# UPF 2: gNB 3-4 (cluster at lat 40.05)
# UPF 3: gNB 5-6 (cluster at lat 40.1)

gnb_locs = [
    GeoPoint(40.0, -74.0),   # gNB 1, UPF 1
    GeoPoint(40.0, -74.05),  # gNB 2, UPF 1
    GeoPoint(40.05, -74.0),  # gNB 3, UPF 2
    GeoPoint(40.05, -74.05), # gNB 4, UPF 2
    GeoPoint(40.1, -74.0),   # gNB 5, UPF 3
    GeoPoint(40.1, -74.05),  # gNB 6, UPF 3
]

upf_locs = [
    GeoPoint(40.0, -74.025),   # UPF 1 (serves gNB 1-2)
    GeoPoint(40.05, -74.025),  # UPF 2 (serves gNB 3-4)
    GeoPoint(40.1, -74.025),   # UPF 3 (serves gNB 5-6)
]

gnb_to_upf = [1, 1, 2, 2, 3, 3]  # gNB->UPF mapping

topology = NetworkTopology(
    gnb_locs, upf_locs, gnb_to_upf,
    GeoPoint[], Int[],
    Municipality[], Dict{String,Vector{Int}}(), Float64[],
    MetaGraph(Graph(), label_type=Tuple{Symbol,Int},
              vertex_data_type=GeoPoint, edge_data_type=Float64)
)

config = SimConfig(
    1, 1,           # min/max sessions (1 per UE for clarity)
    1,              # scale factor (1:1)
    90.0, 85.0, 5.0,  # duration, mean_session, mean_offline
    :single_tier, 0, 1.0,  # scenario, centralized, sampling
    MobilityConfig(
        true, 2.0,  # enabled, update every 2s
        RandomWaypoint(10.0, 0.0, 0.5)  # 10 km/h, 500m per step = ~3km in 60s
    )
)

sim_state = DSim.init_global_state_for_simulation(topology, config)

println("\nTopology:")
println("  UPF 1 → gNB 1-2 (cluster at 40.0, -74.0 to -74.05)")
println("  UPF 2 → gNB 3-4 (cluster at 40.05, -74.0 to -74.05)")
println("  UPF 3 → gNB 5-6 (cluster at 40.1, -74.0 to -74.05)")

# Scenario: 6 agents in two groups
# Group A (3 agents): start near gNB 1, wander locally (Xn handovers)
# Group B (3 agents): start near gNB 1, slowly move toward gNB 5 (cross UPF 1→2→3 = N2 handovers)

println("\nAgent placement:")
println("  Agents 1-3: start near gNB 1 (UPF 1), wander locally → Xn handovers")
println("  Agents 4-6: start near gNB 1 (UPF 1), move toward gNB 5 (UPF 3) → N2 handovers")

sim_env = ConcurrentSim.Simulation()

@process DSim.monitor_metrics(sim_env, sim_state, topology, 1)

# Group A: local wanderers (high pause time = stay in same cell)
for i in 1:3
    @process DSim.user_lifecycle(sim_env, i, sim_state, topology, eMBB)
end

# Group B: cross-domain wanderers (waypoint-seeking = move to distant cells)
for i in 4:6
    @process DSim.user_lifecycle(sim_env, i, sim_state, topology, eMBB)
end

println("\nRunning simulation (90s)...")
run(sim_env, config.duration)

# Results
total_sigma_5g = sim_state.sigma_5g_xn + sim_state.sigma_5g_n2
total_sigma_6g = sim_state.sigma_rupa_intra + sim_state.sigma_rupa_inter
total_ho = sim_state.handover_count

println("\n" * "="^70)
println("RESULTS")
println("="^70)
println("\nHandovers: $total_ho")
println("5G Signaling Costs:")
println("  Xn (600B):  $(sim_state.sigma_5g_xn) bytes ($(sim_state.sigma_5g_xn ÷ 600) events)")
println("  N2 (1150B): $(sim_state.sigma_5g_n2) bytes ($(sim_state.sigma_5g_n2 ÷ 1150) events)")
println("  Total 5G:   $total_sigma_5g bytes")
println("\n6G-RUPA Signaling Costs:")
println("  Intra (200B):  $(sim_state.sigma_rupa_intra) bytes ($(sim_state.sigma_rupa_intra ÷ 200) events)")
println("  Inter (400B):  $(sim_state.sigma_rupa_inter) bytes ($(sim_state.sigma_rupa_inter ÷ 400) events)")
println("  Total RUPA:    $total_sigma_6g bytes")

if total_sigma_5g > 0 && total_sigma_6g > 0
    reduction = (1 - total_sigma_6g / total_sigma_5g) * 100
    println("\n6G-RUPA Advantage: $(round(reduction, digits=1))% less signaling")
end

# Save results
DSim.save_simulation_results("Synthetic", "HandoverForced", sim_state, topology)

println("\nResults saved to results/mobility_evolution_Synthetic_HandoverForced.csv")
println("="^70)
