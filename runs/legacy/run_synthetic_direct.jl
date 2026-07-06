#!/usr/bin/env julia
# Direct synthetic handover: bypass lifecycle, manually trigger handovers with explicit gNB movement

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Graphs
using MetaGraphsNext

import DesJulia6gRupa.Simulation as DSim

println("="^70)
println("DIRECT SYNTHETIC: Manual handover triggering")
println("="^70)

# 3 UPFs, 6 gNBs
gnb_locs = [
    GeoPoint(40.0, -74.0),   # gNB 1, UPF 1
    GeoPoint(40.0, -74.05),  # gNB 2, UPF 1
    GeoPoint(40.05, -74.0),  # gNB 3, UPF 2
    GeoPoint(40.05, -74.05), # gNB 4, UPF 2
    GeoPoint(40.1, -74.0),   # gNB 5, UPF 3
    GeoPoint(40.1, -74.05),  # gNB 6, UPF 3
]

upf_locs = [
    GeoPoint(40.0, -74.025),
    GeoPoint(40.05, -74.025),
    GeoPoint(40.1, -74.025),
]

gnb_to_upf = [1, 1, 2, 2, 3, 3]

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
    MobilityConfig(false, 1.0, NoMobility())
)

sim_state = DSim.init_global_state_for_simulation(topology, config)

println("\nTopology: 3 UPFs, 6 gNBs (2 per UPF)")

# Create 3 sessions at UPF 1
for i in 1:3
    ctx = DSim.create_session_context(1, topology)
    push!(sim_state.upf_sessions_5g[1], ctx)
end

println("Initial state: 3 sessions at UPF 1 (gNB 1-2)")
println("  UPF 1: $(length(sim_state.upf_sessions_5g[1])) sessions")
println("  UPF 2: $(length(sim_state.upf_sessions_5g[2])) sessions")
println("  UPF 3: $(length(sim_state.upf_sessions_5g[3])) sessions")

# Test 1: Xn handover (gNB 1-2, both UPF 1)
println("\n" * "-"^70)
println("Test 1: Xn handover (gNB 1→2, same UPF 1)")
println("-"^70)
agent_sessions = copy(sim_state.upf_sessions_5g[1][1:3])
DSim.handle_handover_5g!(sim_state, topology, agent_sessions, 1, 1, 1, 1, 1, 1)
println("σ_5g_xn += 600: $(sim_state.sigma_5g_xn) bytes")
@assert sim_state.sigma_5g_xn == 600 "Xn handover not recorded!"

# Test 2: N2 handover (UPF 1→2)
println("\n" * "-"^70)
println("Test 2: N2 handover (UPF 1→2)")
println("-"^70)
agent_sessions = [sim_state.upf_sessions_5g[1][1]]  # Move first session
DSim.handle_handover_5g!(sim_state, topology, agent_sessions, 1, 2, 1, 2, 1, 1)
println("σ_5g_n2 += 1150: $(sim_state.sigma_5g_n2) bytes")
@assert sim_state.sigma_5g_n2 == 1150 "N2 handover not recorded!"

# Test 3: Another N2 (UPF 2→3)
println("\n" * "-"^70)
println("Test 3: N2 handover (UPF 2→3)")
println("-"^70)
agent_sessions = [sim_state.upf_sessions_5g[2][1]]  # Session moved to UPF 2 in Test 2
DSim.handle_handover_5g!(sim_state, topology, agent_sessions, 2, 3, 2, 3, 1, 1)
println("σ_5g_n2 += 1150: $(sim_state.sigma_5g_n2) bytes")
@assert sim_state.sigma_5g_n2 == 2300 "Second N2 handover not recorded!"

# Test 4: RUPA intra-domain
println("\n" * "-"^70)
println("Test 4: 6G-RUPA intra-domain renumbering (gNB 1→2)")
println("-"^70)
DSim.handle_handover_6grupa!(sim_state, topology, 1, 2, 1, 1, 1, 1)
println("σ_rupa_intra += 200: $(sim_state.sigma_rupa_intra) bytes")
@assert sim_state.sigma_rupa_intra == 200 "Intra-domain renumbering not recorded!"

# Test 5: RUPA inter-domain
println("\n" * "-"^70)
println("Test 5: 6G-RUPA inter-domain renumbering (gNB 1→5, UPF 1→3)")
println("-"^70)
DSim.handle_handover_6grupa!(sim_state, topology, 1, 5, 1, 3, 1, 1)
println("σ_rupa_inter += 400: $(sim_state.sigma_rupa_inter) bytes")
@assert sim_state.sigma_rupa_inter == 400 "Inter-domain renumbering not recorded!"

# Summary
println("\n" * "="^70)
println("SUMMARY")
println("="^70)
total_5g = sim_state.sigma_5g_xn + sim_state.sigma_5g_n2
total_6g = sim_state.sigma_rupa_intra + sim_state.sigma_rupa_inter
println("\n5G:")
println("  Xn (600B):  $(sim_state.sigma_5g_xn) bytes (1 event)")
println("  N2 (1150B): $(sim_state.sigma_5g_n2) bytes (2 events)")
println("  Total:      $total_5g bytes")
println("\n6G-RUPA:")
println("  Intra (200B): $(sim_state.sigma_rupa_intra) bytes (1 event)")
println("  Inter (400B): $(sim_state.sigma_rupa_inter) bytes (1 event)")
println("  Total:        $total_6g bytes")

if total_5g > 0 && total_6g > 0
    reduction = (1 - total_6g / total_5g) * 100
    println("\n6G-RUPA Advantage: $(round(reduction, digits=1))% lower signaling")
end

println("\n✓ Direct handover simulation validated all σ increments")
println("="^70)
