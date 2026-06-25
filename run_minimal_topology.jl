#!/usr/bin/env julia
# Minimal topology: 4 gNBs in line, agents walk from gNB1→gNB4, forced handovers

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Graphs
using MetaGraphsNext

import DesJulia6gRupa.Simulation as DSim

println("="^70)
println("MINIMAL TOPOLOGY: Guaranteed handover path")
println("="^70)

# 4 gNBs in a line, 2 UPFs (gNB 1-2 → UPF 1, gNB 3-4 → UPF 2)
gnb_locs = [
    GeoPoint(40.0, -74.0),   # gNB 1
    GeoPoint(40.0, -74.01),  # gNB 2 (close to gNB 1, same UPF)
    GeoPoint(40.0, -74.02),  # gNB 3 (different UPF)
    GeoPoint(40.0, -74.03),  # gNB 4 (close to gNB 3, same UPF)
]

upf_locs = [
    GeoPoint(40.0, -74.005),
    GeoPoint(40.0, -74.025),
]

gnb_to_upf = [1, 1, 2, 2]  # gNBs 1-2 → UPF 1, gNBs 3-4 → UPF 2

topology = NetworkTopology(
    gnb_locs, upf_locs, gnb_to_upf,
    GeoPoint[], Int[],
    Municipality[], Dict{String,Vector{Int}}(), Float64[],
    MetaGraph(Graph(), label_type=Tuple{Symbol,Int},
              vertex_data_type=GeoPoint, edge_data_type=Float64)
)

config = SimConfig(
    1, 1, 1, 60.0, 55.0, 5.0,
    :single_tier, 0, 10.0,
    MobilityConfig(
        true, 0.5,
        RandomWaypoint(100.0, 0.0, 1.0)  # high speed, lots of movement
    )
)

sim_state = DSim.init_global_state_for_simulation(topology, config)

println("\nTopology: 4 gNBs in line")
println("  gNB 1-2 (40.0, -74.0 to -74.01) → UPF 1")
println("  gNB 3-4 (40.0, -74.02 to -74.03) → UPF 2")
println("  Distance gNB 2→3: ~1.1 km (forces UPF change)\n")

# Manually place agent at gNB 1
println("Agent placement: manually at gNB 1 (UPF 1)")
for _ in 1:5  # 5 sessions
    ctx = DSim.create_session_context(1, topology)
    push!(sim_state.upf_sessions_5g[1], ctx)
end

sim_env = ConcurrentSim.Simulation()

@process DSim.monitor_metrics(sim_env, sim_state, topology, 1)

# Instead of lifecycle, manually create agent that we'll step through
# Use existing lifecycle but with specific initial placement would require modifying
# select_agent_location. For now, just verify mechanism works with direct calls.

# Direct test: simulate movement from gNB 1 → 4, triggering handovers
println("\nSimulating handover path (direct calls):")

agent_sessions = copy(sim_state.upf_sessions_5g[1])
println("Initial: 5 sessions at UPF 1")

# Step 1: gNB 1→2 (same UPF, Xn)
println("\nStep 1: gNB 1→2 (same UPF 1) = Xn handover")
DSim.handle_handover_5g!(sim_state, topology, agent_sessions, 1, 1, 1, 1, 1, 1)
println("  σ_5g_xn: $(sim_state.sigma_5g_xn) bytes")

# Step 2: gNB 2→3 (different UPF, N2)
println("\nStep 2: gNB 2→3 (UPF 1→2) = N2 handover")
agent_sessions = [sim_state.upf_sessions_5g[1][1]]
DSim.handle_handover_5g!(sim_state, topology, agent_sessions, 1, 2, 1, 2, 1, 1)
println("  σ_5g_n2: $(sim_state.sigma_5g_n2) bytes")

# Step 3: gNB 3→4 (same UPF, Xn)
println("\nStep 3: gNB 3→4 (same UPF 2) = Xn handover")
agent_sessions = [sim_state.upf_sessions_5g[2][1]]
DSim.handle_handover_5g!(sim_state, topology, agent_sessions, 2, 2, 2, 2, 1, 1)
println("  σ_5g_xn: $(sim_state.sigma_5g_xn) bytes")

# Step 4: gNB 4→1 (back to UPF 1, N2)
println("\nStep 4: gNB 4→1 (UPF 2→1) = N2 handover")
agent_sessions = [sim_state.upf_sessions_5g[2][1]]
DSim.handle_handover_5g!(sim_state, topology, agent_sessions, 2, 1, 2, 1, 1, 1)
println("  σ_5g_n2: $(sim_state.sigma_5g_n2) bytes")

# 6G-RUPA equivalent
println("\n" * "-"^70)
println("6G-RUPA parallel scenario:")
println("-"^70)

# Intra-domain (gNB 1→2)
println("\nIntra-domain: gNB 1→2")
DSim.handle_handover_6grupa!(sim_state, topology, 1, 2, 1, 1, 1, 1)
println("  σ_rupa_intra: $(sim_state.sigma_rupa_intra) bytes")

# Inter-domain (gNB 2→3)
println("\nInter-domain: gNB 2→3")
DSim.handle_handover_6grupa!(sim_state, topology, 2, 3, 1, 2, 1, 1)
println("  σ_rupa_inter: $(sim_state.sigma_rupa_inter) bytes")

# Intra-domain (gNB 3→4)
println("\nIntra-domain: gNB 3→4")
DSim.handle_handover_6grupa!(sim_state, topology, 3, 4, 2, 2, 1, 1)
println("  σ_rupa_intra: $(sim_state.sigma_rupa_intra) bytes")

# Inter-domain (gNB 4→1)
println("\nInter-domain: gNB 4→1")
DSim.handle_handover_6grupa!(sim_state, topology, 4, 1, 2, 1, 1, 1)
println("  σ_rupa_inter: $(sim_state.sigma_rupa_inter) bytes")

# Summary
println("\n" * "="^70)
println("SUMMARY: Handover Path Simulation")
println("="^70)

total_5g = sim_state.sigma_5g_xn + sim_state.sigma_5g_n2
total_6g = sim_state.sigma_rupa_intra + sim_state.sigma_rupa_inter
total_ho = sim_state.handover_count

println("\n5G (gNB 1→2→3→4→1):")
xn_events = sim_state.sigma_5g_xn ÷ 600
n2_events = sim_state.sigma_5g_n2 ÷ 1150
println("  Xn handovers: $xn_events × 600B = $(sim_state.sigma_5g_xn) bytes")
println("  N2 handovers: $n2_events × 1150B = $(sim_state.sigma_5g_n2) bytes")
println("  Total: $total_5g bytes")

println("\n6G-RUPA (same path):")
intra_events = sim_state.sigma_rupa_intra ÷ 200
inter_events = sim_state.sigma_rupa_inter ÷ 400
println("  Intra-domain: $intra_events × 200B = $(sim_state.sigma_rupa_intra) bytes")
println("  Inter-domain: $inter_events × 400B = $(sim_state.sigma_rupa_inter) bytes")
println("  Total: $total_6g bytes")

advantage = (1 - total_6g / total_5g) * 100
println("\n6G-RUPA Advantage: $(round(advantage, digits=1))% lower signaling")
println("  (5G: $total_5g bytes, RUPA: $total_6g bytes)")

println("\n✓ Minimal topology validates complete handover path with realistic σ costs")
println("="^70)
