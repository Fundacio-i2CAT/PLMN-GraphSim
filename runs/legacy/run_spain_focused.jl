#!/usr/bin/env julia
# Focused Spain region: smaller topology, agents started at boundary pairs

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Graphs
using MetaGraphsNext
using Statistics

import DesJulia6gRupa.Simulation as DSim

println("="^70)
println("SPAIN FOCUSED REGION: Boundary-based placement + high mobility")
println("="^70)

# Load Spain topology
data_dir = "/home/sergio/phd/PLMN-GraphSim/data/spain"
mccs = [214]
config = SimConfig(
    1, 2, 1000, 180.0, 175.0, 5.0,
    :single_tier, 0, 10.0,
    MobilityConfig(
        true, 1.0,
        RandomWaypoint(100.0, 2.0, 8.0)  # high speed, larger jumps, pause time for local clustering
    )
)

println("Loading Spain topology (8 UPFs, subset of gNBs)...")
valid_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
valid_paths = filter(isfile, valid_paths)

if isempty(valid_paths)
    println("❌ Data not found")
    exit(1)
end

# Load topology with 8 UPFs (reduced from 52 for better handover clustering)
topology = DSim.load_and_deploy_network(valid_paths, 7, 8, data_dir, config)

println("Topology loaded: $(length(topology.gnb_locations)) gNBs, $(length(topology.upf_locations)) UPFs")

# Analyze UPF spatial distribution for boundary identification
upf_locs = topology.upf_locations
println("\nUPF locations (first 4):")
for i in 1:min(4, length(upf_locs))
    println("  UPF $i: $(upf_locs[i])")
end

# Identify boundary gNBs: for each UPF pair, find closest gNB from each
println("\nIdentifying boundary gNB pairs...")
boundary_pairs = Tuple{Int, Int}[]
for upf1 in 1:min(length(topology.upf_locations)-1, 3)
    upf2 = upf1 + 1
    loc1 = topology.upf_locations[upf1]
    loc2 = topology.upf_locations[upf2]

    # Find gNBs served by each UPF
    gnbs_upf1 = findall(x -> x == upf1, topology.gnb_to_upf_map)
    gnbs_upf2 = findall(x -> x == upf2, topology.gnb_to_upf_map)

    if !isempty(gnbs_upf1) && !isempty(gnbs_upf2)
        # Find closest pair
        min_dist = Inf
        best_pair = (gnbs_upf1[1], gnbs_upf2[1])

        for g1 in gnbs_upf1, g2 in gnbs_upf2
            d = abs((topology.gnb_locations[g1].lat - topology.gnb_locations[g2].lat)) +
                abs((topology.gnb_locations[g1].lon - topology.gnb_locations[g2].lon))
            if d < min_dist
                min_dist = d
                best_pair = (g1, g2)
            end
        end

        push!(boundary_pairs, best_pair)
        println("  Pair ($best_pair): gNB $(best_pair[1]) (UPF $upf1) ↔ gNB $(best_pair[2]) (UPF $upf2)")
    end
end

println("\nInitializing simulation with $(length(boundary_pairs) * 50) agents...")
println("  Strategy: 50 agents per boundary pair + 50 random")

sim_state = DSim.init_global_state_for_simulation(topology, config)
sim_env = ConcurrentSim.Simulation()

@process DSim.monitor_metrics(sim_env, sim_state, topology, config.scale_factor)

# Spawn agents
# - 50 per boundary pair (should cross domains)
# - 50 random (baseline)
for (idx, (gnb1, gnb2)) in enumerate(boundary_pairs)
    for i in 1:50
        agent_id = (idx-1)*50 + i
        @process DSim.user_lifecycle(sim_env, agent_id, sim_state, topology, eMBB)
    end
end

# Random agents
for i in 1:50
    agent_id = length(boundary_pairs) * 50 + i
    @process DSim.user_lifecycle(sim_env, agent_id, sim_state, topology, eMBB)
end

println("Running simulation (180s)...\n")
run(sim_env, config.duration)

# Analyze results
total_5g = sim_state.sigma_5g_xn + sim_state.sigma_5g_n2 + sim_state.sigma_roam_5g
total_6g = sim_state.sigma_rupa_intra + sim_state.sigma_rupa_inter + sim_state.sigma_roam_rupa
total_ho = sim_state.handover_count

println("\n" * "="^70)
println("RESULTS")
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
        println("  Xn (600B):  $(sim_state.sigma_5g_xn) bytes ($xn_events events, $xn_pct%)")
    end
    if sim_state.sigma_5g_n2 > 0
        n2_events = sim_state.sigma_5g_n2 ÷ 1150
        println("  N2 (1150B): $(sim_state.sigma_5g_n2) bytes ($n2_events events, $n2_pct%)")
    end
    if sim_state.sigma_roam_5g > 0
        println("  Roam: $(sim_state.sigma_roam_5g) bytes")
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
        println("  Roam: $(sim_state.sigma_roam_rupa) bytes")
    end

    if total_5g > 0 && total_6g > 0
        advantage = (1 - total_6g / total_5g) * 100
        println("\n6G-RUPA Advantage: $(round(advantage, digits=1))% lower signaling")
    end

    # Save results
    DSim.save_simulation_results("Spain", "Focused_8upf_high_mobility", sim_state, topology)
    println("\n✓ Results saved to results/")
else
    println("\n⚠ No handovers generated (mobility/placement still insufficient)")
    println("Next: inspect gNB distribution or increase agent clustering")
end

println("="^70)
