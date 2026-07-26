using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.DataLoading
using DesJulia6gRupa.Types
using Graphs
using MetaGraphsNext

# Iberia two-country composition (§7.4 phase 2, docs/agents/countries/portugal.md
# "Iberia scenario sketch"): two operator fields composed into ONE topology; an agent
# whose nearest gNB flips operator has geometrically crossed the border — that IS the
# roaming trigger. HR keeps the anchor in the home country, so the roaming
# path-stretch (serving visited edge UPF → pinned home PSA) becomes measurable.

@testset "Iberia composition (§7.4 phase 2)" begin

    _graph() = MetaGraph(Graph(), label_type = Tuple{Symbol, Int},
                         vertex_data_type = GeoPoint, edge_data_type = Float64)

    # Home operator field: 2 gNBs → 2 edge UPFs → 1 PSA, one municipality (pop 3000).
    function _home_topology()
        NetworkTopology(
            [GeoPoint(40.0, -4.0), GeoPoint(40.0, -5.0)],
            [GeoPoint(40.0, -4.0), GeoPoint(40.0, -5.0)],
            [1, 2],
            [GeoPoint(40.0, -4.5)], [1, 1],
            [Municipality("h1", "HomeTown", 3000, GeoPoint(40.0, -4.0), 0.0, nothing)],
            Dict{String,Vector{Int}}(), [1.0],
            _graph(),
        )
    end

    # Visited operator field: 1 gNB → 1 edge UPF → 1 PSA, one municipality (pop 1000).
    function _visited_topology()
        NetworkTopology(
            [GeoPoint(40.0, -7.0)],
            [GeoPoint(40.0, -7.0)],
            [1],
            [GeoPoint(40.0, -7.0)], [1],
            [Municipality("v1", "VisitedTown", 1000, GeoPoint(40.0, -7.0), 0.0, nothing)],
            Dict{String,Vector{Int}}(), [1.0],
            _graph(),
        )
    end

    @testset "legacy constructor tags everything operator 1" begin
        t = _home_topology()
        @test t.gnb_operator == [1, 1]
        @test t.psa_operator == [1]
        @test Simulation.serving_operator(t, 1) == 1
        @test Simulation.serving_operator(t, 2) == 1
    end

    @testset "compose_topologies: offsets, tags, merged population" begin
        home, visited = _home_topology(), _visited_topology()
        t = DataLoading.compose_topologies(home, visited)

        # Concatenation with home first, visited offset after.
        @test length(t.gnb_locations) == 3
        @test length(t.upf_locations) == 3
        @test length(t.centralized_upf_locations) == 2
        @test t.gnb_to_upf_map == [1, 2, 3]          # visited gNB → edge UPF 3
        @test t.edge_upf_parent_map == [1, 1, 2]     # visited edge → PSA 2
        # Operator tags: home = 1, visited = 2.
        @test t.gnb_operator == [1, 1, 2]
        @test t.psa_operator == [1, 2]
        @test Simulation.serving_operator(t, 3) == 2
        # Merged population-weighted placement: 3000 vs 1000.
        @test length(t.municipalities) == 2
        @test isapprox(t.municipality_probs, [0.75, 0.25]; atol = 1e-9)
    end

    @testset "border crossing on composed topology: roam branch + roam stretch" begin
        t = DataLoading.compose_topologies(_home_topology(), _visited_topology())
        scale = 1000
        config = SimConfig(1, 1, scale, 10.0, 5.0, 5.0, :two_tier, 2, 1.0,
                           MobilityConfig(true, 1.0, RandomWaypoint(5.0, 0.0, 1.0)),
                           RoamingConfig(:reestablish, 0.0))
        state = Simulation.init_global_state_for_simulation(t, config)

        # Session established at HOME edge UPF 2 → anchor = home PSA 1.
        ctx = Simulation.create_session_context(2, t)
        @test ctx.metadata.anchor_upf_index == 1
        push!(state.upf_sessions_5g[2], ctx)

        # Move inside home first: edge 2 → 1 (same operator) = ordinary N2, no roam.
        s = Simulation.dispatch_handover!(state, t, [ctx], 2, 1, 2, 1, 2, 1, 1, 1)
        @test state.sigma_roam_5g == 0
        @test state.roam_stretch_samples == 0
        @test state.anchor_stretch_samples == 1      # domestic sample accumulated

        # Cross the border: gNB 1 → 3, edge 1 → 3, operator 1 → 2.
        s = Simulation.dispatch_handover!(state, t, s, 1, 3, 1, 3, 1, 3, 1, 2)
        @test state.sigma_roam_5g == 3250
        @test state.session_breaks_5g == 1 * scale
        @test state.roam_entries == 1
        # HR: anchor still the HOME PSA.
        @test s[1].metadata.anchor_upf_index == 1

        # Roaming path-stretch sampled into the ROAM bucket, not the domestic one.
        @test state.roam_stretch_samples == 1
        @test state.anchor_stretch_samples == 1      # unchanged
        # Pinned leg: visited edge UPF 3 → home PSA 1 (a country-scale hairpin);
        # optimal leg: nearest PSA overall = the visited PSA (distance 0 here).
        d_pinned = Types.haversine_distance(t.upf_locations[3], t.centralized_upf_locations[1])
        @test isapprox(state.roam_dist_5g_sum, d_pinned; rtol = 1e-6)
        @test state.roam_dist_opt_sum ≈ 0.0 atol = 1e-9
        @test state.roam_dist_5g_sum > 100.0         # hundreds of km, the §7 payoff
    end
end
