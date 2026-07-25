using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.DataLoading
using DesJulia6gRupa.Types

if !isdefined(Main, :TestFixtures)
    include("TestFixtures.jl")
end
using .TestFixtures

# Iberia two-country composition (§7.4 phase 2). The composition mechanics
# (offsets, tags, merged probs, 2-ary delegation) are the K=2 case of
# FederationTests and are covered there; this file keeps ONLY the unique
# end-to-end that federation does not: the country-scale roaming path-stretch
# (serving visited edge UPF → pinned HOME PSA) with its measured magnitude.
# Bespoke geometry (PSA offset from its edges) is needed for the domestic
# stretch sample, so this keeps its own builders rather than op_field.

@testset "Iberia border crossing: roam branch + country-scale hairpin (§7.4)" begin

    # Home: 2 gNBs → 2 edge UPFs → 1 PSA offset to (40,-4.5); pop 3000.
    _home() = NetworkTopology(
        [GeoPoint(40.0, -4.0), GeoPoint(40.0, -5.0)],
        [GeoPoint(40.0, -4.0), GeoPoint(40.0, -5.0)], [1, 2],
        [GeoPoint(40.0, -4.5)], [1, 1],
        [Municipality("h1", "HomeTown", 3000, GeoPoint(40.0, -4.0), 0.0, nothing)],
        Dict{String,Vector{Int}}(), [1.0], mock_graph())
    # Visited: 1 gNB → 1 edge UPF → 1 PSA; pop 1000; ~200 km from home.
    _visited() = NetworkTopology(
        [GeoPoint(40.0, -7.0)], [GeoPoint(40.0, -7.0)], [1],
        [GeoPoint(40.0, -7.0)], [1],
        [Municipality("v1", "VisitedTown", 1000, GeoPoint(40.0, -7.0), 0.0, nothing)],
        Dict{String,Vector{Int}}(), [1.0], mock_graph())

    t = DataLoading.compose_topologies(_home(), _visited())
    scale = 1000
    config = SimConfig(1, 1, scale, 10.0, 5.0, 5.0, :two_tier, 2, 1.0,
                       MobilityConfig(true, 1.0, RandomWaypoint(5.0, 0.0, 1.0)),
                       RoamingConfig(:reestablish, 0.0))
    state = Simulation.init_global_state_for_simulation(t, config)

    # Session at HOME edge UPF 2 → anchor = home PSA 1.
    ctx = Simulation.create_session_context(2, t)
    @test ctx.metadata.anchor_upf_index == 1
    push!(state.upf_sessions_5g[2], ctx)

    # Domestic move (edge 2 → 1, same operator): ordinary N2, no roam, domestic
    # stretch sample accumulated (pinned PSA 40,-4.5 ≠ serving edge).
    s = Simulation.dispatch_handover!(state, t, [ctx], 2, 1, 2, 1, 2, 1, 1, 1)
    @test state.sigma_roam_5g == 0
    @test state.roam_stretch_samples == 0
    @test state.anchor_stretch_samples == 1

    # Cross the border (gNB 1 → 3, edge 1 → 3, operator 1 → 2): roam branch.
    s = Simulation.dispatch_handover!(state, t, s, 1, 3, 1, 3, 1, 3, 1, 2)
    @test state.sigma_roam_5g == SIGMA_ROAM_5G_REEST
    @test state.session_breaks_5g == 1 * scale
    @test state.roam_entries == 1
    @test s[1].metadata.anchor_upf_index == 1        # HR: anchor stays home

    # Path-stretch lands in the ROAM bucket: visited edge 3 → pinned home PSA 1,
    # a country-scale hairpin; optimal egress is the nearest PSA (the visited one).
    @test state.roam_stretch_samples == 1
    @test state.anchor_stretch_samples == 1          # unchanged
    d_pinned = Types.haversine_distance(t.upf_locations[3], t.centralized_upf_locations[1])
    @test isapprox(state.roam_dist_5g_sum, d_pinned; rtol = 1e-6)
    @test state.roam_dist_opt_sum ≈ 0.0 atol = 1e-9
    @test state.roam_dist_5g_sum > 100.0             # hundreds of km — the §7.4 payoff
end
