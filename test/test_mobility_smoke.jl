#!/usr/bin/env julia
# Quick smoke test: mobility enabled, verify σ counters appear in CSV

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Graphs
using MetaGraphsNext

import DesJulia6gRupa.Simulation as DSim

# Minimal config for fast test
config = SimConfig(
    1, 2,  # min/max sessions
    1000,  # scale factor
    10.0, 9.0, 1.0,  # duration, mean_session, mean_offline
    :single_tier, 0, 1.0,  # scenario, num_centralized, sampling_interval
    MobilityConfig(true, 0.5, RandomWaypoint(5.0, 0.0, 1.0))  # mobility
)

# Tiny topology: 2 gNBs, 1 UPF, 5 agents
gnb_locs = [GeoPoint(40.0, -3.7), GeoPoint(40.1, -3.8)]
upf_locs = [GeoPoint(40.05, -3.75)]
gnb_to_upf = [1, 1]

topology = NetworkTopology(
    gnb_locs, upf_locs, gnb_to_upf,
    GeoPoint[], Int[],
    Municipality[], Dict{String,Vector{Int}}(), Float64[],
    MetaGraph(Graph(), label_type=Tuple{Symbol,Int},
              vertex_data_type=GeoPoint, edge_data_type=Float64)
)

sim_state = DSim.init_global_state_for_simulation(topology, config)

# Run simulation
env = ConcurrentSim.Simulation()
@process DSim.monitor_metrics(env, sim_state, topology, 1)

for agent_id in 1:5
    @process DSim.user_lifecycle(env, agent_id, sim_state, topology, eMBB)
end

run(env, config.duration)

# Save results
DSim.save_simulation_results("SmokeTest", "MobilityEnabled", sim_state, topology)

# Check CSV was generated with σ columns
results_dir = joinpath(dirname(@__DIR__), "results")
csv_path = joinpath(results_dir, "mobility_evolution_SmokeTest_MobilityEnabled.csv")

if isfile(csv_path)
    lines = readlines(csv_path)
    header = split(lines[1], ',')

    required_columns = [
        "Time", "Handovers_Cumulative",
        "Sigma_5G_Xn", "Sigma_5G_N2",
        "Sigma_RUPA_Intra", "Sigma_RUPA_Inter",
        "Sigma_Roam_5G", "Sigma_Roam_RUPA"
    ]

    missing = filter(col -> !(col in header), required_columns)

    if isempty(missing)
        println("✓ CSV has all σ columns")
        println("  Columns: $(join(header, ", "))")
        println("  Data rows: $(length(lines)-1)")
        println("\n  Sample (first 3 rows):")
        for row in lines[1:min(3, length(lines))]
            println("    $row")
        end
    else
        println("✗ Missing columns: $(join(missing, ", "))")
        exit(1)
    end
else
    println("✗ CSV not found: $csv_path")
    exit(1)
end

println("\n✓ Smoke test PASSED")
