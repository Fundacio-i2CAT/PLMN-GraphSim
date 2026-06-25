#!/usr/bin/env julia
# Spain coarse subset: subsample 500 gNBs from 46k, maintain geography, enable handovers

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Distributions
using Clustering
using Statistics
using Graphs
using MetaGraphsNext

import DesJulia6gRupa.Simulation as DSim

println("="^70)
println("SPAIN COARSE SUBSET: 500 gNBs, 8 UPFs, realistic deployment scale")
println("="^70)

# Load full Spain topology
data_dir = "/home/sergio/phd/PLMN-GraphSim/data/spain"
mccs = [214]

println("Loading Spain data (46k gNBs)...")
valid_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
valid_paths = filter(isfile, valid_paths)

if isempty(valid_paths)
    println("❌ Data not found")
    exit(1)
end

# Load with full density first
topology_full = DSim.load_and_deploy_network(valid_paths, 7, 8, data_dir, SimConfig(1,2,1000,1,1,1,:single_tier,0,1,MobilityConfig()))

# Subsample to 500 gNBs while preserving geography
println("Subsampling to 500 gNBs (maintaining geographic distribution)...")
n_sample = 500
indices = sample(1:length(topology_full.gnb_locations), n_sample, replace=false)
gnb_locs_subset = topology_full.gnb_locations[indices]

println("  $(length(gnb_locs_subset)) gNBs selected")

# Re-cluster subsampled gNBs into 8 UPF regions using k-means
println("Re-clustering 500 gNBs into 8 UPF regions...")
n_upfs = 8

# Convert to matrix for clustering: D × N (2 features, 500 points)
lats = [p.lat for p in gnb_locs_subset]
lons = [p.lon for p in gnb_locs_subset]
coords = hcat(lats, lons)'  # 500 × 2 → transpose to 2 × 500

# K-means clustering
result = kmeans(coords, n_upfs)
cluster_assignments = result.assignments

# Convert centers back to GeoPoint (result.centers is 2 × K)
upf_locs_subset = [GeoPoint(result.centers[1, i], result.centers[2, i]) for i in 1:n_upfs]

# Map each gNB to its cluster
gnb_to_upf_subset = cluster_assignments

println("  UPF locations:")
for i in 1:n_upfs
    n_gnbs = count(x -> x == i, gnb_to_upf_subset)
    println("    UPF $i: $(upf_locs_subset[i]) ($n_gnbs gNBs)")
end

# Create new topology with coarse subset
topology = NetworkTopology(
    gnb_locs_subset, upf_locs_subset, gnb_to_upf_subset,
    GeoPoint[], Int[],
    Municipality[], Dict{String,Vector{Int}}(), Float64[],
    MetaGraph(Graphs.Graph(), label_type=Tuple{Symbol,Int},
              vertex_data_type=GeoPoint, edge_data_type=Float64)
)

# Simulation config
config = SimConfig(
    1, 2, 1000, 240.0, 235.0, 5.0,
    :single_tier, 0, 10.0,
    MobilityConfig(
        true, 1.0,
        RandomWaypoint(80.0, 1.0, 6.0)  # realistic vehicular speeds
    )
)

println("\nInitializing simulation: 400 agents × 240s...")
println("  Strategy: 50 agents per boundary pair + remaining distributed")

sim_state = DSim.init_global_state_for_simulation(topology, config)
sim_env = ConcurrentSim.Simulation()

@process DSim.monitor_metrics(sim_env, sim_state, topology, config.scale_factor)

# Identify boundary pairs
boundary_pairs = Tuple{Int, Int}[]
for upf1 in 1:min(length(topology.upf_locations)-1, 6)
    upf2 = upf1 + 1
    gnbs_upf1 = findall(x -> x == upf1, gnb_to_upf_subset)
    gnbs_upf2 = findall(x -> x == upf2, gnb_to_upf_subset)

    if !isempty(gnbs_upf1) && !isempty(gnbs_upf2)
        min_dist = Inf
        best_pair = (gnbs_upf1[1], gnbs_upf2[1])
        for g1 in gnbs_upf1, g2 in gnbs_upf2
            d = abs((gnb_locs_subset[g1].lat - gnb_locs_subset[g2].lat)) +
                abs((gnb_locs_subset[g1].lon - gnb_locs_subset[g2].lon))
            if d < min_dist
                min_dist = d
                best_pair = (g1, g2)
            end
        end
        push!(boundary_pairs, best_pair)
    end
end

println("  Boundary pairs: $(length(boundary_pairs))")
for (i, (g1, g2)) in enumerate(boundary_pairs)
    println("    Pair $i: gNB $g1 (UPF $(gnb_to_upf_subset[g1])) ↔ gNB $g2 (UPF $(gnb_to_upf_subset[g2]))")
end

# Spawn agents: 50 per boundary pair, rest random
for (idx, (gnb1, gnb2)) in enumerate(boundary_pairs)
    for i in 1:50
        agent_id = (idx-1)*50 + i
        @process DSim.user_lifecycle(sim_env, agent_id, sim_state, topology, eMBB)
    end
end

# Remaining agents
for i in 1:200
    agent_id = length(boundary_pairs)*50 + i
    @process DSim.user_lifecycle(sim_env, agent_id, sim_state, topology, eMBB)
end

println("Running simulation (240s)...\n")
run(sim_env, config.duration)

# Analyze results
total_5g = sim_state.sigma_5g_xn + sim_state.sigma_5g_n2 + sim_state.sigma_roam_5g
total_6g = sim_state.sigma_rupa_intra + sim_state.sigma_rupa_inter + sim_state.sigma_roam_rupa
total_ho = sim_state.handover_count

println("\n" * "="^70)
println("RESULTS: Spain Coarse Subset (500 gNBs, 8 UPFs, 400 agents)")
println("="^70)

if total_ho > 0
    xn_pct = 100 * sim_state.sigma_5g_xn / max(1, total_5g)
    n2_pct = 100 * sim_state.sigma_5g_n2 / max(1, total_5g)
    intra_pct = 100 * sim_state.sigma_rupa_intra / max(1, total_6g)
    inter_pct = 100 * sim_state.sigma_rupa_inter / max(1, total_6g)

    println("\nHandovers: $total_ho")
    println("\n5G Signaling (Total: $total_5g bytes)")
    if sim_state.sigma_5g_xn > 0
        xn_events = sim_state.sigma_5g_xn ÷ 600
        println("  Xn (600B):  $(sim_state.sigma_5g_xn) bytes ($xn_events events, $(round(xn_pct, digits=1))%)")
    end
    if sim_state.sigma_5g_n2 > 0
        n2_events = sim_state.sigma_5g_n2 ÷ 1150
        println("  N2 (1150B): $(sim_state.sigma_5g_n2) bytes ($n2_events events, $(round(n2_pct, digits=1))%)")
    end

    println("\n6G-RUPA Signaling (Total: $total_6g bytes)")
    if sim_state.sigma_rupa_intra > 0
        intra_events = sim_state.sigma_rupa_intra ÷ 200
        println("  Intra (200B): $(sim_state.sigma_rupa_intra) bytes ($intra_events events, $(round(intra_pct, digits=1))%)")
    end
    if sim_state.sigma_rupa_inter > 0
        inter_events = sim_state.sigma_rupa_inter ÷ 400
        println("  Inter (400B): $(sim_state.sigma_rupa_inter) bytes ($inter_events events, $(round(inter_pct, digits=1))%)")
    end

    if total_5g > 0 && total_6g > 0
        advantage = (1 - total_6g / total_5g) * 100
        println("\n✓ 6G-RUPA Advantage: $(round(advantage, digits=1))% lower signaling")
        println("  (5G: $total_5g bytes, RUPA: $total_6g bytes)")
    end

    DSim.save_simulation_results("Spain", "Coarse500_8upf_national", sim_state, topology)
    println("\n✓ Results saved: mobility_evolution_Spain_Coarse500_8upf_national.csv")
else
    println("\n⚠ No handovers (may need more aggressive parameters)")
end

println("="^70)
