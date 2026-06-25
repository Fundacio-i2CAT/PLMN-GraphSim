#!/usr/bin/env julia
# Reuse minimal_topology.jl's proven pattern on Spain coarse subset

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
println("SPAIN MINIMAL PATTERN: Proven σ tracking on coarse subset")
println("="^70)

# Load & subsample Spain
data_dir = "/home/sergio/phd/PLMN-GraphSim/data/spain"
mccs = [214]

println("Loading Spain...")
valid_paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in mccs]
valid_paths = filter(isfile, valid_paths)

topology_full = DSim.load_and_deploy_network(valid_paths, 7, 8, data_dir, SimConfig(1,2,1000,1,1,1,:single_tier,0,1,MobilityConfig()))

n_sample = 500
indices = sample(1:length(topology_full.gnb_locations), n_sample, replace=false)
gnb_locs_subset = topology_full.gnb_locations[indices]

# Re-cluster
lats = [p.lat for p in gnb_locs_subset]
lons = [p.lon for p in gnb_locs_subset]
coords = hcat(lats, lons)'

result = kmeans(coords, 8)
gnb_to_upf_subset = result.assignments
upf_locs_subset = [GeoPoint(result.centers[1, i], result.centers[2, i]) for i in 1:8]

topology = NetworkTopology(
    gnb_locs_subset, upf_locs_subset, gnb_to_upf_subset,
    GeoPoint[], Int[],
    Municipality[], Dict{String,Vector{Int}}(), Float64[],
    MetaGraph(Graph(), label_type=Tuple{Symbol,Int},
              vertex_data_type=GeoPoint, edge_data_type=Float64)
)

# Reuse minimal_topology.jl handover test pattern
sim_state = DSim.init_global_state_for_simulation(topology, SimConfig(1,2,1000,60,55,5,:single_tier,0,10,MobilityConfig()))
sim_env = ConcurrentSim.Simulation()

@process DSim.monitor_metrics(sim_env, sim_state, topology, 1)

# Identify first UPF boundary pair
upf1_gnbs = findall(x -> x == 1, gnb_to_upf_subset)
upf2_gnbs = findall(x -> x == 2, gnb_to_upf_subset)

if !isempty(upf1_gnbs) && !isempty(upf2_gnbs)
    gnb1 = upf1_gnbs[1]
    gnb2 = upf2_gnbs[1]

    println("\nHandover test:")
    println("  UPF 1→1 (Xn, gNB 1→2):")

    # Create sessions at UPF 1
    for _ in 1:5
        ctx = DSim.create_session_context(1, topology)
        push!(sim_state.upf_sessions_5g[1], ctx)
    end

    println("    σ_5g_xn before: $(sim_state.sigma_5g_xn)")

    # Xn handover (same UPF, minimal_topology.jl pattern)
    agent_sessions = copy(sim_state.upf_sessions_5g[1])
    DSim.handle_handover_5g!(sim_state, topology, agent_sessions, 1, 2, 1, 1, 1, 1)

    println("    σ_5g_xn after: $(sim_state.sigma_5g_xn)")

    # N2 handover (different UPF)
    println("\n  UPF 1→2 (N2, gNB 2→gNB2_upf2):")
    println("    σ_5g_n2 before: $(sim_state.sigma_5g_n2)")

    agent_sessions = [sim_state.upf_sessions_5g[1][1]]
    DSim.handle_handover_5g!(sim_state, topology, agent_sessions, 2, gnb2, 1, 2, 1, 1)

    println("    σ_5g_n2 after: $(sim_state.sigma_5g_n2)")

    # Summary
    total_5g = sim_state.sigma_5g_xn + sim_state.sigma_5g_n2
    println("\n" * "="^70)
    println("RESULTS")
    println("="^70)
    println("5G Total: $total_5g bytes")
    println("  Xn (2 × 600B): $(sim_state.sigma_5g_xn) bytes")
    println("  N2 (1 × 1150B): $(sim_state.sigma_5g_n2) bytes")

    if total_5g > 0
        println("\n✓ σ mechanism works on Spain coarse subset")
    end
else
    println("\n⚠ Boundary gNBs not found")
end

println("="^70)
