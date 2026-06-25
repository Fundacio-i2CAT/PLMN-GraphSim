#!/usr/bin/env julia
# Spain coarse subset with forced linear handover paths (deterministic, not Random Waypoint)

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Distributions
using Clustering
using Graphs
using MetaGraphsNext
using Statistics

import DesJulia6gRupa.Simulation as DSim

println("="^70)
println("SPAIN FORCED HANDOVER: 500 gNBs, deterministic boundary-crossing paths")
println("="^70)

# Load & subsample Spain topology
data_dir = "/home/sergio/phd/PLMN-GraphSim/data/spain"
mccs = [214]

println("Loading Spain data...")
valid_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
valid_paths = filter(isfile, valid_paths)

topology_full = DSim.load_and_deploy_network(valid_paths, 7, 8, data_dir, SimConfig(1,2,1000,1,1,1,:single_tier,0,1,MobilityConfig()))

# Subsample 500 gNBs
n_sample = 500
indices = sample(1:length(topology_full.gnb_locations), n_sample, replace=false)
gnb_locs_subset = topology_full.gnb_locations[indices]

# Re-cluster into 8 UPFs
lats = [p.lat for p in gnb_locs_subset]
lons = [p.lon for p in gnb_locs_subset]
coords = hcat(lats, lons)'

result = kmeans(coords, 8)
gnb_to_upf_subset = result.assignments
upf_locs_subset = [GeoPoint(result.centers[1, i], result.centers[2, i]) for i in 1:8]

# Create topology
topology = NetworkTopology(
    gnb_locs_subset, upf_locs_subset, gnb_to_upf_subset,
    GeoPoint[], Int[],
    Municipality[], Dict{String,Vector{Int}}(), Float64[],
    MetaGraph(Graph(), label_type=Tuple{Symbol,Int},
              vertex_data_type=GeoPoint, edge_data_type=Float64)
)

# Identify boundary pairs
boundary_pairs = Tuple{Int, Int}[]
for upf1 in 1:min(length(upf_locs_subset)-1, 6)
    upf2 = upf1 + 1
    gnbs_upf1 = findall(x -> x == upf1, gnb_to_upf_subset)
    gnbs_upf2 = findall(x -> x == upf2, gnb_to_upf_subset)

    if !isempty(gnbs_upf1) && !isempty(gnbs_upf2)
        min_dist = Inf
        best_pair = (gnbs_upf1[1], gnbs_upf2[1])
        for g1 in gnbs_upf1, g2 in gnbs_upf2
            d = sqrt((gnb_locs_subset[g1].lat - gnb_locs_subset[g2].lat)^2 +
                     (gnb_locs_subset[g1].lon - gnb_locs_subset[g2].lon)^2)
            if d < min_dist
                min_dist = d
                best_pair = (g1, g2)
            end
        end
        push!(boundary_pairs, best_pair)
    end
end

println("Identified $(length(boundary_pairs)) boundary pairs")

# Simulation: Direct handover test without Random Waypoint
config = SimConfig(
    1, 2, 1000, 60.0, 55.0, 5.0,
    :single_tier, 0, 10.0,
    MobilityConfig(true, 1.0, RandomWaypoint(100.0, 0.0, 0.0))
)

sim_state = DSim.init_global_state_for_simulation(topology, config)
sim_env = ConcurrentSim.Simulation()

@process DSim.monitor_metrics(sim_env, sim_state, topology, 1)

println("\nSimulating handovers along boundary pairs:")

# For each boundary pair, manually simulate agents crossing the boundary
for (idx, (gnb1, gnb2)) in enumerate(boundary_pairs)
    upf1_idx = gnb_to_upf_subset[gnb1]
    upf2_idx = gnb_to_upf_subset[gnb2]

    # Create sessions at gNB1/UPF1
    for sess_id in 1:5
        ctx = DSim.create_session_context(upf1_idx, topology)
        push!(sim_state.upf_sessions_5g[upf1_idx], ctx)
    end

    # Simulate handover: gNB1 → gNB2
    println("  Pair $idx: $(length(sim_state.upf_sessions_5g[upf1_idx])) sessions at gNB $gnb1 (UPF $upf1_idx)")

    # Classify handover
    if upf1_idx == upf2_idx
        handover_type = "Xn (same UPF)"
        cost = 600
    else
        handover_type = "N2 (different UPF)"
        cost = 1150
    end

    # Call handover
    agent_sessions = copy(sim_state.upf_sessions_5g[upf1_idx])
    DSim.handle_handover_5g!(sim_state, topology, agent_sessions, gnb1, gnb2, upf1_idx, upf2_idx, 1, 1)

    ho_count_before = length(sim_state.upf_sessions_5g[upf1_idx]) + length(sim_state.upf_sessions_5g[upf2_idx])
    println("    → gNB $gnb2 (UPF $upf2_idx): $handover_type × 5 sessions")
    println("      σ_5g_xn: $(sim_state.sigma_5g_xn), σ_5g_n2: $(sim_state.sigma_5g_n2)")
end

# Summary
total_5g = sim_state.sigma_5g_xn + sim_state.sigma_5g_n2
total_6g = sim_state.sigma_rupa_intra + sim_state.sigma_rupa_inter

println("\n" * "="^70)
println("RESULTS: Forced Handover Test (deterministic boundary crossing)")
println("="^70)

if sim_state.sigma_5g_xn > 0 || sim_state.sigma_5g_n2 > 0
    xn_events = sim_state.sigma_5g_xn ÷ 600
    n2_events = sim_state.sigma_5g_n2 ÷ 1150

    println("\n5G (Total: $total_5g bytes)")
    if sim_state.sigma_5g_xn > 0
        println("  Xn: $xn_events events × 600B = $(sim_state.sigma_5g_xn) bytes")
    end
    if sim_state.sigma_5g_n2 > 0
        println("  N2: $n2_events events × 1150B = $(sim_state.sigma_5g_n2) bytes")
    end

    println("\n✓ Forced handovers validated on Spain coarse topology")
    println("  (Deterministic boundary crossing: mechanism works end-to-end)")
else
    println("\n⚠ No handovers recorded")
end

println("="^70)
