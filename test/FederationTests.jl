using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.DataLoading
using DesJulia6gRupa.Types
using Graphs
using MetaGraphsNext

# Multi-operator federation (§7.5.1): K operator fields composed into ONE shared
# topology — the "network of networks" scenario. In the federation vision an agent
# attaches to whichever member's coverage is best, so inter-operator crossings become
# routine events; the per-crossing cost decides whether the vision is viable. The
# composition itself is the RUPA claim: K members enroll once each into a shared
# internetwork DIF (O(K)), versus 5G's bilateral agreement/N32 mesh (O(K(K-1)/2),
# GSMA NG.113 §4.2 Model 1; Models 2.3/3/4 introduce hubs precisely to compress it).

@testset "Federation composition (§7.5.1)" begin

    _graph() = MetaGraph(Graph(), label_type = Tuple{Symbol, Int},
                         vertex_data_type = GeoPoint, edge_data_type = Float64)

    # Minimal operator field: n gNBs (1:1 with edge UPFs) → 1 PSA, one municipality.
    function _field(n::Int, lon0::Float64, pop::Int, code::String)
        NetworkTopology(
            [GeoPoint(40.0, lon0 - (i - 1)) for i in 1:n],
            [GeoPoint(40.0, lon0 - (i - 1)) for i in 1:n],
            collect(1:n),
            [GeoPoint(40.0, lon0)], fill(1, n),
            [Municipality(code, code, pop, GeoPoint(40.0, lon0), 0.0, nothing)],
            Dict{String,Vector{Int}}(), [1.0],
            _graph(),
        )
    end

    @testset "K-ary compose: offsets, tags, merged population" begin
        a, b, c = _field(2, -4.0, 3000, "a"), _field(1, -7.0, 1000, "b"), _field(3, -1.0, 4000, "c")
        t = DataLoading.compose_topologies([a, b, c])

        @test length(t.gnb_locations) == 6
        @test length(t.upf_locations) == 6
        @test length(t.centralized_upf_locations) == 3
        # Edge/PSA indices offset per preceding member.
        @test t.gnb_to_upf_map == [1, 2, 3, 4, 5, 6]
        @test t.edge_upf_parent_map == [1, 1, 2, 3, 3, 3]
        # Operator tags 1..K in composition order.
        @test t.gnb_operator == [1, 1, 2, 3, 3, 3]
        @test t.psa_operator == [1, 2, 3]
        @test Simulation.serving_operator(t, 3) == 2
        @test Simulation.serving_operator(t, 6) == 3
        # Merged population weights: 3000/1000/4000.
        @test isapprox(t.municipality_probs, [0.375, 0.125, 0.5]; atol = 1e-9)
    end

    @testset "overlapping members: shared municipalities counted once" begin
        # Two operators covering the SAME country (same municipality code) plus one
        # foreign member: the shared municipality must not double its population
        # weight just because two members serve it.
        a = _field(2, -4.0, 3000, "es")   # operator 1, Spain
        b = _field(1, -4.5, 3000, "es")   # operator 2, also Spain (same muni code)
        c = _field(1, -7.0, 1000, "pt")   # operator 3, Portugal
        t = DataLoading.compose_topologies([a, b, c])
        @test length(t.municipalities) == 2                 # es once, pt once
        @test isapprox(t.municipality_probs, [0.75, 0.25]; atol = 1e-9)
        # Infrastructure NOT deduped: all members' gNBs/PSAs present.
        @test length(t.gnb_locations) == 4
        @test t.psa_operator == [1, 2, 3]
    end

    @testset "K-ary compose: custom operator ids" begin
        t = DataLoading.compose_topologies([_field(1, -4.0, 100, "a"), _field(1, -7.0, 100, "b")];
                                           operators = [7, 6])
        @test t.gnb_operator == [7, 6]
        @test t.psa_operator == [7, 6]
    end

    @testset "2-ary compose still delegates (Iberia backward compat)" begin
        a, b = _field(2, -4.0, 3000, "a"), _field(1, -7.0, 1000, "b")
        t2 = DataLoading.compose_topologies(a, b)
        tk = DataLoading.compose_topologies([a, b])
        @test t2.gnb_operator == tk.gnb_operator
        @test t2.gnb_to_upf_map == tk.gnb_to_upf_map
        @test t2.edge_upf_parent_map == tk.edge_upf_parent_map
        @test t2.municipality_probs == tk.municipality_probs
    end

    @testset "crossings among 3 members each charge; intra-member does not" begin
        # Fields overlap-adjacent so gNB indices are unambiguous:
        # op1 = gNBs 1-2 (edges 1-2, PSA 1), op2 = gNB 3 (edge 3, PSA 2),
        # op3 = gNBs 4-6 (edges 4-6, PSA 3).
        t = DataLoading.compose_topologies(
            [_field(2, -4.0, 3000, "a"), _field(1, -7.0, 1000, "b"), _field(3, -1.0, 4000, "c")])
        scale = 1000
        config = SimConfig(1, 1, scale, 10.0, 5.0, 5.0, :two_tier, 3, 1.0,
                           MobilityConfig(true, 1.0, RandomWaypoint(5.0, 0.0, 1.0)),
                           RoamingConfig(:reestablish, 0.0))
        state = Simulation.init_global_state_for_simulation(t, config)

        ctx = Simulation.create_session_context(1, t)
        @test ctx.metadata.anchor_upf_index == 1
        push!(state.upf_sessions_5g[1], ctx)

        # op1 → op2 crossing.
        s = Simulation.dispatch_handover!(state, t, [ctx], 1, 3, 1, 3, 1, 3, 1, 2)
        @test state.roam_entries == 1
        @test state.sigma_roam_5g == 3250
        # op2 → op3 crossing: second federation-member change, charged again.
        s = Simulation.dispatch_handover!(state, t, s, 3, 4, 3, 4, 3, 4, 2, 3)
        @test state.roam_entries == 2
        @test state.sigma_roam_5g == 2 * 3250
        @test state.session_breaks_5g == 2 * scale
        # op3 internal move: gNB 4 → 5, same operator — NO roam charge.
        s = Simulation.dispatch_handover!(state, t, s, 4, 5, 4, 5, 4, 5, 3, 3)
        @test state.roam_entries == 2
        @test state.sigma_roam_5g == 2 * 3250
        # Anchor stays pinned at home PSA 1 throughout (HR).
        @test s[1].metadata.anchor_upf_index == 1
        # ROAM stretch samples on EVERY handover while abroad (anchor operator ≠
        # serving operator), not only at crossings — the HR hairpin persists for
        # the whole visit: 2 crossings + 1 intra-op3 move = 3 samples.
        @test state.roam_stretch_samples == 3
        @test state.anchor_stretch_samples == 0
    end
end
