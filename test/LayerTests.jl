using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.DataLoading
using DesJulia6gRupa.Types
using Graphs
using MetaGraphsNext
using JSON3

# Graph-of-graphs layer model (recursive internetworking).
#
# A federation is a DAG of layers: each layer is one graph whose vertices are
# GUPF instances; a physical node participating in k layers hosts k GUPF
# instances, each with its own forwarding table (recursion happens at border
# nodes). Handover classification falls out of the recursion: a move renumbers
# upward through the layer DAG until it reaches a layer whose aggregate is
# unchanged — the climb depth IS the event class. This generalizes the flat
# operator-tag model (2 levels: member + implicit internetwork) to N layers
# over M sublayers, and lets forwarding state be accounted per (node, layer).

@testset "Layer model (graph of graphs)" begin

    _graph() = MetaGraph(Graph(), label_type = Tuple{Symbol, Int},
                         vertex_data_type = GeoPoint, edge_data_type = Float64)

    # Minimal operator field: n gNBs (1:1 with edge UPFs) → 1 PSA.
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

    # 3 members: A (2 domains), B (1 domain), C (3 domains); composed indices:
    # edge UPFs 1..6 (A:1-2, B:3, C:4-6), PSAs 1..3 → node ids 7..9.
    _members() = [_field(2, -4.0, 3000, "a"), _field(1, -7.0, 1000, "b"),
                  _field(3, -1.0, 4000, "c")]
    _composed() = DataLoading.compose_topologies(_members())

    @testset "stack construction from composed topology" begin
        t = _composed()
        stack = Simulation.build_layer_stack(t)

        # One member layer per operator tag + one internetwork layer.
        @test length(stack.layers) == 4
        member_ids = [l.id for l in stack.layers if l.level == 0]
        inet = Simulation.layer_by_name(stack, "internetwork")
        @test length(member_ids) == 3
        @test inet.level == 1
        @test sort(stack.floats_over[inet.id]) == sort(member_ids)

        # Member layer A: GUPFs at its 2 edge-UPF nodes + its PSA node.
        la = Simulation.layer_by_name(stack, "member-1")
        @test length(la.gupfs) == 3
        # Internetwork layer: one border GUPF per member PSA node.
        @test length(inet.gupfs) == 3
    end

    @testset "recursion point: border node hosts one GUPF per layer" begin
        t = _composed()
        stack = Simulation.build_layer_stack(t)
        # PSA of member A = physical node 7 (6 edge UPFs + PSA index 1).
        instances = Simulation.gupfs_at_node(stack, 7)
        @test length(instances) == 2
        @test sort(unique(g.layer_id for g in instances)) ==
              sort([Simulation.layer_by_name(stack, "member-1").id,
                    Simulation.layer_by_name(stack, "internetwork").id])
        # Independent forwarding tables per instance (different scopes).
        member_tbl, inet_tbl = (g.forwarding_table for g in instances)
        @test member_tbl !== inet_tbl
    end

    @testset "per-(node, layer) forwarding-table sizes" begin
        t = _composed()
        stack = Simulation.build_layer_stack(t)
        la = Simulation.layer_by_name(stack, "member-1")
        inet = Simulation.layer_by_name(stack, "internetwork")

        # Edge GUPF (member layer): one entry per served gNB + default route up.
        edge_g = la.gupfs[Simulation.gupf_index_at(la, 1)]   # edge UPF node 1
        @test length(edge_g.forwarding_table) == 1 + 1
        # PSA GUPF (member layer): one entry per child edge domain + default up.
        psa_g = la.gupfs[Simulation.gupf_index_at(la, 7)]
        @test length(psa_g.forwarding_table) == 2 + 1
        # Border GUPF (internetwork layer): one aggregate entry per member.
        # ΔS argument: table size scales with #members, NOT #users.
        border_g = inet.gupfs[Simulation.gupf_index_at(inet, 7)]
        @test length(border_g.forwarding_table) == 3
    end

    @testset "attachment + classification: flat federation (climb 1)" begin
        t = _composed()
        stack = Simulation.build_layer_stack(t)
        la = Simulation.layer_by_name(stack, "member-1")
        lc = Simulation.layer_by_name(stack, "member-3")

        # Attachment from a composed gNB index: (member layer, edge domain).
        a1 = Simulation.attachment_of(stack, t, 1)   # gNB 1 → op 1, edge UPF 1
        a2 = Simulation.attachment_of(stack, t, 2)   # gNB 2 → op 1, edge UPF 2
        c1 = Simulation.attachment_of(stack, t, 4)   # gNB 4 → op 3, edge UPF 4
        @test a1.layer_id == la.id && a1.domain_id == 1
        @test c1.layer_id == lc.id && c1.domain_id == 4

        # Same domain → intra; same layer, different domain → inter; different
        # member layer → crossing with climb 1 through the internetwork layer.
        r = Simulation.classify_move(stack, a1, a1)
        @test r.class == :intra && r.climb == 0
        r = Simulation.classify_move(stack, a1, a2)
        @test r.class == :inter && r.climb == 0 && r.common_layer == la.id
        r = Simulation.classify_move(stack, a1, c1)
        @test r.class == :crossing && r.climb == 1
        @test r.common_layer == Simulation.layer_by_name(stack, "internetwork").id
    end

    @testset "N+2 recursion: exchange layers under a root (climb 2)" begin
        # The M,O,P,Q case: members 1,2 under exchange X; member 3 under
        # exchange Y; X and Y under root R. Crossing 1→2 climbs 1 (via X);
        # crossing 1→3 climbs 2 (via R). Tags cannot express this; the DAG can.
        t = _composed()
        stack = Simulation.build_layer_stack(t; internetwork = false)
        m = [Simulation.layer_by_name(stack, "member-$i").id for i in 1:3]
        x = Simulation.add_federation_layer!(stack, [m[1], m[2]]; name = "exchange-x")
        y = Simulation.add_federation_layer!(stack, [m[3]]; name = "exchange-y")
        r_id = Simulation.add_federation_layer!(stack, [x, y]; name = "root")

        @test Simulation.layer_by_name(stack, "exchange-x").level == 1
        @test Simulation.layer_by_name(stack, "root").level == 2

        a = Simulation.Attachment(m[1], 1)
        b = Simulation.Attachment(m[2], 3)
        c = Simulation.Attachment(m[3], 4)
        r1 = Simulation.classify_move(stack, a, b)
        @test r1.class == :crossing && r1.climb == 1 && r1.common_layer == x
        r2 = Simulation.classify_move(stack, a, c)
        @test r2.class == :crossing && r2.climb == 2 && r2.common_layer == r_id
    end

    @testset "disconnected members raise" begin
        t = _composed()
        stack = Simulation.build_layer_stack(t; internetwork = false)
        m = [Simulation.layer_by_name(stack, "member-$i").id for i in 1:3]
        Simulation.add_federation_layer!(stack, [m[1], m[2]]; name = "exchange-x")
        a = Simulation.Attachment(m[1], 1)
        c = Simulation.Attachment(m[3], 4)
        @test_throws ArgumentError Simulation.classify_move(stack, a, c)
    end

    @testset "enrollment: NTN member joins the internetwork after the fact" begin
        t = _composed()
        stack = Simulation.build_layer_stack(t)
        inet = Simulation.layer_by_name(stack, "internetwork")
        n_before = length(inet.gupfs)

        # Satellite member: GUPFs on fresh physical node ids (one per satellite).
        sat = Simulation.add_member_layer!(stack, [100, 101, 102]; name = "ntn-starlink")
        Simulation.enroll!(stack, inet.id, sat)

        @test sat in stack.floats_over[inet.id]
        # Enrollment adds ONE border GUPF for the new member (O(K) membership).
        @test length(inet.gupfs) == n_before + 1

        # Terrestrial ↔ satellite crossing is an ordinary member crossing.
        la = Simulation.layer_by_name(stack, "member-1")
        r = Simulation.classify_move(stack, Simulation.Attachment(la.id, 1),
                                     Simulation.Attachment(sat, 100))
        @test r.class == :crossing && r.climb == 1 && r.common_layer == inet.id
        # Satellite → satellite switch inside the member: inter (network moves
        # under the UE, but the layer aggregate is unchanged).
        r = Simulation.classify_move(stack, Simulation.Attachment(sat, 100),
                                     Simulation.Attachment(sat, 101))
        @test r.class == :inter
    end

    @testset "σ charging equivalence with legacy dispatch" begin
        # The layer classification must reproduce the flat model's σ counters
        # exactly — this is the INFOCOM safety net. Drive the same move set
        # through legacy dispatch_handover! and through charge_move! on twin
        # states; every σ counter must match.
        t = _composed()
        stack = Simulation.build_layer_stack(t)
        config = SimConfig(1, 1, 1, 100.0, 10.0, 5.0, :two_tier, 3, 1.0)
        legacy = Simulation.init_global_state_for_simulation(t, config)
        layered = Simulation.init_global_state_for_simulation(t, config)

        # Moves: (old_gnb, new_gnb) covering intra (same UPF impossible here —
        # 1:1 gNB:UPF, so use same-gNB no-op skip), inter, crossing.
        moves = [(1, 2), (2, 1), (1, 4), (4, 5), (5, 6), (6, 3), (3, 1)]
        for (og, ng) in moves
            ou, nu = t.gnb_to_upf_map[og], t.gnb_to_upf_map[ng]
            oo, no = Simulation.serving_operator(t, og), Simulation.serving_operator(t, ng)

            ctx = Simulation.create_session_context(ou, t, ou, oo)
            push!(legacy.upf_sessions_5g[ou], ctx)
            Simulation.dispatch_handover!(legacy, t, [ctx], og, ng, ou, nu,
                                          ou, nu, oo, no)

            old_att = Simulation.attachment_of(stack, t, og)
            new_att = Simulation.attachment_of(stack, t, ng)
            Simulation.charge_move!(layered, stack, old_att, new_att;
                                    num_sessions = 1)
        end

        for f in (:sigma_5g_xn, :sigma_5g_n2, :sigma_roam_5g,
                  :sigma_rupa_intra, :sigma_rupa_inter, :sigma_roam_rupa,
                  :handover_count, :roam_entries, :session_breaks_5g)
            @test getfield(layered, f) == getfield(legacy, f)
        end
    end

    @testset "ΔS_core = 0: crossings never touch forwarding tables" begin
        t = _composed()
        stack = Simulation.build_layer_stack(t)
        config = SimConfig(1, 1, 1, 100.0, 10.0, 5.0, :two_tier, 3, 1.0)
        state = Simulation.init_global_state_for_simulation(t, config)

        snapshot = [copy(g.forwarding_table) for l in stack.layers for g in l.gupfs]
        for (og, ng) in [(1, 2), (1, 4), (4, 6), (6, 3)]
            Simulation.charge_move!(state, stack,
                                    Simulation.attachment_of(stack, t, og),
                                    Simulation.attachment_of(stack, t, ng);
                                    num_sessions = 1)
        end
        after = [copy(g.forwarding_table) for l in stack.layers for g in l.gupfs]
        @test snapshot == after
    end

    @testset "JSON export for the layer visualization" begin
        t = _composed()
        stack = Simulation.build_layer_stack(t)
        path = joinpath(mktempdir(), "layers.json")
        Simulation.export_layer_stack_json(stack, path)
        doc = JSON3.read(read(path, String))
        @test length(doc.layers) == 4
        names = [l.name for l in doc.layers]
        @test "internetwork" in names && "member-1" in names
        inet = doc.layers[findfirst(==("internetwork"), names)]
        @test length(inet.gupfs) == 3
        @test all(haskey(g, :node_id) && haskey(g, :table_size) &&
                  haskey(g, :lat) && haskey(g, :lon) for g in inet.gupfs)
        @test !isempty(doc.floats_over)
    end
end
