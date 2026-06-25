using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.Types
using Graphs
using MetaGraphsNext

@testset "Mobility (PoC)" begin

    @testset "MobilityConfig defaults preserve legacy behaviour" begin
        cfg = MobilityConfig()
        @test cfg.enabled == false
        @test cfg.model isa NoMobility

        # Legacy 9-arg SimConfig constructor still works and disables mobility.
        sc = SimConfig(1, 2, 1000, 10.0, 5.0, 5.0, :single_tier, 0, 1.0)
        @test sc.mobility.enabled == false
        @test sc.mobility.model isa NoMobility
    end

    # Helper: walk an agent for T ticks of dt seconds, return (total_path_km, net_km).
    function _walk(model, start, T, dt)
        st = MobilityState(start, 0.0, 0.0, 0.0, 0.0)
        cur = start
        path = 0.0
        for _ in 1:T
            nl = Simulation.step_position(model, cur, st, dt)
            path += Types.haversine_distance(cur, nl)
            cur = nl
        end
        return path, Types.haversine_distance(start, cur)
    end

    @testset "spatial index matches brute-force nearest gNB" begin
        # Property check: grid query == O(n) reference. 150 random points over a
        # 500-gNB field is plenty to catch ring/boundary bugs (was 1000×2000 —
        # overkill that dominated the assertion count).
        gnbs = [GeoPoint(40.0 + 3*rand(), -5.0 + 6*rand()) for _ in 1:500]
        topo = NetworkTopology(
            gnbs, [GeoPoint(41.0,-3.0)], fill(1, length(gnbs)),
            GeoPoint[], Int[],
            Municipality[], Dict{String,Vector{Int}}(), Float64[],
            MetaGraph(Graph(), label_type=Tuple{Symbol,Int}, vertex_data_type=GeoPoint, edge_data_type=Float64),
        )
        grid = Simulation.build_gnb_grid(gnbs)
        mismatches = 0
        for _ in 1:150
            q = GeoPoint(40.0 + 3*rand(), -5.0 + 6*rand())
            Simulation.nearest_gnb(grid, gnbs, q) == Simulation.find_serving_gnb_brute(topo, q) || (mismatches += 1)
        end
        @test mismatches == 0
        # the cached fast path used by the sim must also agree
        q = GeoPoint(41.5, -2.5)
        @test Simulation.find_serving_gnb(topo, q) == Simulation.find_serving_gnb_brute(topo, q)
    end

    @testset "step_position: NoMobility is a no-op" begin
        loc = GeoPoint(40.0, -3.7)
        state = MobilityState(loc, 0.0, 0.0, 0.0, 0.0)
        @test Simulation.step_position(NoMobility(), loc, state, 10.0) === loc
    end

    @testset "step_position: per-step jump cap respected" begin
        loc = GeoPoint(40.0, -3.7)
        m = RandomWaypoint(5.0, 0.0, 1.0)  # 5 km/h, 1 km cap per jump
        state = MobilityState(loc, 0.0, 0.0, 0.0, 0.0)
        d = Types.haversine_distance(loc, Simulation.step_position(m, loc, state, 100_000.0))
        @test d <= m.max_jump_km + 1e-6
    end

    # Regression for the frozen-agent bug: the old RWP state machine re-entered
    # pause after every waypoint pick and returned `loc` forever, so an agent
    # never translated. The previous test only checked an UPPER bound
    # (`d <= cap`), which a zero-displacement no-op trivially satisfied. These
    # assert the agent ACTUALLY travels at its configured speed.
    @testset "step_position: RWP travels at configured speed (no pause)" begin
        loc = GeoPoint(40.0, -3.7)
        T, dt = 600, 1.0
        for v in (5.0, 50.0)
            path, net = _walk(RandomWaypoint(v, 0.0, 20.0), loc, T, dt)
            expected = v * (T * dt) / 3600.0          # km covered at speed v
            @test isapprox(path, expected; rtol = 0.02)
            @test net > 0.1                            # not stuck in place
        end
    end

    @testset "step_position: GaussMarkov travels (ballistic) at configured speed" begin
        loc = GeoPoint(40.0, -3.7)
        T, dt = 600, 1.0
        path, net = _walk(GaussMarkov(80.0, 0.85, 5.0), loc, T, dt)
        @test isapprox(path, 80.0 * (T * dt) / 3600.0; rtol = 0.02)
        @test net > 1.0                                # sustained direction, covers ground
    end

    @testset "step_position: RWP pause halts then resumes (no permanent freeze)" begin
        loc = GeoPoint(40.0, -3.7)
        # Small jumps (0.5 km) so the agent actually REACHES waypoints and pauses
        # repeatedly within the horizon; with large jumps it never arrives and the
        # pause never engages (the assumption the first draft of this test missed).
        path, _ = _walk(RandomWaypoint(50.0, 10.0, 0.5), loc, 600, 1.0)
        @test path > 1.0                               # frozen-agent bug => exactly 0.0
        # Pausing must reduce distance vs free-running (pause=0) at the same speed.
        free, _ = _walk(RandomWaypoint(50.0, 0.0, 0.5), loc, 600, 1.0)
        @test path < free
    end

    @testset "handle_handover_5g! migrates sessions and bumps counter" begin
        # Build a tiny topology with 2 UPFs, single-tier (no parent map).
        gnb_locs = [GeoPoint(0.0, 0.0), GeoPoint(0.1, 0.1)]
        upf_locs = [GeoPoint(0.0, 0.0), GeoPoint(0.1, 0.1)]
        topology = NetworkTopology(
            gnb_locs, upf_locs, [1, 2],
            GeoPoint[], Int[],  # no two-tier
            Municipality[], Dict{String,Vector{Int}}(), Float64[],
            MetaGraph(Graph(), label_type = Tuple{Symbol, Int},
                      vertex_data_type = GeoPoint, edge_data_type = Float64),
        )
        config = SimConfig(1, 1, 1000, 10.0, 5.0, 5.0, :single_tier, 0, 1.0,
                           MobilityConfig(true, 1.0, RandomWaypoint(5.0, 0.0, 1.0)))
        state = Simulation.init_global_state_for_simulation(topology, config)

        # Manually create one session on UPF 1 and register it as the agent's.
        ctx = Simulation.create_session_context(1, topology)
        push!(state.upf_sessions_5g[1], ctx)
        agent_sessions = [ctx]

        @test length(state.upf_sessions_5g[1]) == 1
        @test length(state.upf_sessions_5g[2]) == 0
        @test state.sigma_5g_n2 == 0

        new_sessions = Simulation.handle_handover_5g!(state, topology,
                                                      agent_sessions, 1, 2, 1, 2, 1, 1)

        @test length(state.upf_sessions_5g[1]) == 0
        @test length(state.upf_sessions_5g[2]) == 1
        @test length(new_sessions) == 1
        @test state.sigma_5g_n2 == 1150

        # Same-UPF call is a no-op.
        Simulation.handle_handover_5g!(state, topology, new_sessions, 2, 2, 2, 2, 1, 1)
        @test state.sigma_5g_n2 == 1150
    end

    @testset "handle_handover_6grupa! counts local renumbering events" begin
        topology = NetworkTopology(
            [GeoPoint(0.0, 0.0)], [GeoPoint(0.0, 0.0)], [1],
            GeoPoint[], Int[],
            Municipality[], Dict{String,Vector{Int}}(), Float64[],
            MetaGraph(Graph(), label_type = Tuple{Symbol, Int},
                      vertex_data_type = GeoPoint, edge_data_type = Float64),
        )
        config = SimConfig(1, 1, 1000, 1.0, 1.0, 1.0, :single_tier, 0, 1.0,
                           MobilityConfig(true, 1.0, RandomWaypoint(5.0, 0.0, 1.0)))
        state = Simulation.init_global_state_for_simulation(topology, config)

        # Renumbering is FLAT across levels (mobility-formal-model.md §3.4): the
        # destination domain's aggregate prefix already exists in the topology, so
        # a moving UE just adopts an address under it — same procedure cost
        # regardless of how far it moves. No core prefix op (that was the old,
        # wrong 400 B inter-domain model).
        @test state.sigma_rupa_intra == 0
        Simulation.handle_handover_6grupa!(state, topology, 1, 2, 1, 1, 1, 1)
        @test state.sigma_rupa_intra == 200          # local renumber
        # Same gNB -> no-op.
        Simulation.handle_handover_6grupa!(state, topology, 2, 2, 1, 1, 1, 1)
        @test state.sigma_rupa_intra == 200

        # Cross-domain renumber: classified as inter (event classifier) but charged
        # the SAME flat 200 B, not 400.
        Simulation.handle_handover_6grupa!(state, topology, 2, 3, 1, 2, 1, 1)
        @test state.sigma_rupa_inter == 200          # flat renumber, not 400
        @test state.sigma_rupa_intra == 200          # intra untouched
    end

    @testset "core forwarding-state churn: 5G O(n) per-session, RUPA 0" begin
        # The headline mobility result: a 5G handover must (re)write per-session
        # forwarding state at the UPF, scaled by the real user population
        # (scale_factor) -> O(n). A 6G-RUPA renumber touches NO core forwarding
        # state at any level (ΔS_core = 0) -> 0 writes.
        gnb_locs = [GeoPoint(0.0, 0.0), GeoPoint(0.1, 0.1)]
        upf_locs = [GeoPoint(0.0, 0.0), GeoPoint(0.1, 0.1)]
        topology = NetworkTopology(
            gnb_locs, upf_locs, [1, 2],
            GeoPoint[], Int[],
            Municipality[], Dict{String,Vector{Int}}(), Float64[],
            MetaGraph(Graph(), label_type = Tuple{Symbol, Int},
                      vertex_data_type = GeoPoint, edge_data_type = Float64),
        )
        scale = 1000
        config = SimConfig(1, 2, scale, 10.0, 5.0, 5.0, :single_tier, 0, 1.0,
                           MobilityConfig(true, 1.0, RandomWaypoint(5.0, 0.0, 1.0)))
        state = Simulation.init_global_state_for_simulation(topology, config)

        ctx1 = Simulation.create_session_context(1, topology)
        ctx2 = Simulation.create_session_context(1, topology)
        push!(state.upf_sessions_5g[1], ctx1); push!(state.upf_sessions_5g[1], ctx2)
        agent_sessions = [ctx1, ctx2]

        @test state.core_writes_5g == 0
        @test state.core_writes_rupa == 0

        # N2 handover, 2 sessions, scale_factor 1000 => 2*1000 per-session writes.
        Simulation.handle_handover_5g!(state, topology, agent_sessions, 1, 2, 1, 2, 1, 1)
        @test state.core_writes_5g == 2 * scale

        # 6G-RUPA renumber: zero core writes, at any level.
        Simulation.handle_handover_6grupa!(state, topology, 1, 2, 1, 2, 1, 1)
        @test state.core_writes_rupa == 0
    end

    # Integration test for the wired-together dispatch. The unit tests above pass
    # each handler in isolation, but two bugs lived only in how Core.jl combined
    # them: (1) it mutated current_domain BEFORE the 6G-RUPA call, so inter-domain
    # renumbering never fired; (2) both handlers bumped handover_count, doubling it.
    # dispatch_handover! is the single entry point Core uses; these assertions fail
    # on either regression.
    @testset "dispatch_handover! drives 5G+6G consistently, counts once" begin
        gnb_locs = [GeoPoint(0.0, 0.0), GeoPoint(0.05, 0.05), GeoPoint(0.1, 0.1)]
        upf_locs = [GeoPoint(0.0, 0.0), GeoPoint(0.1, 0.1)]
        topology = NetworkTopology(
            gnb_locs, upf_locs, [1, 1, 2],
            GeoPoint[], Int[],
            Municipality[], Dict{String,Vector{Int}}(), Float64[],
            MetaGraph(Graph(), label_type = Tuple{Symbol, Int},
                      vertex_data_type = GeoPoint, edge_data_type = Float64),
        )
        config = SimConfig(1, 1, 1000, 10.0, 5.0, 5.0, :single_tier, 0, 1.0,
                           MobilityConfig(true, 1.0, RandomWaypoint(5.0, 0.0, 1.0)))
        state = Simulation.init_global_state_for_simulation(topology, config)

        ctx = Simulation.create_session_context(1, topology)
        push!(state.upf_sessions_5g[1], ctx)
        sessions = [ctx]

        # Intra-domain hop: gNB 1->2, same UPF/domain 1 => Xn + RUPA intra, one HO.
        sessions = Simulation.dispatch_handover!(state, topology, sessions,
                                                 1, 2, 1, 1, 1, 1, 1, 1)
        @test state.sigma_5g_xn == 600
        @test state.sigma_rupa_intra == 200
        @test state.sigma_5g_n2 == 0
        @test state.sigma_rupa_inter == 0
        @test state.handover_count == 1               # counted once, not twice

        # Inter-domain hop: gNB 2->3, UPF/domain 1->2 => N2 (graded, 1150) + RUPA
        # inter classified but charged flat renumber (200), one HO.
        sessions = Simulation.dispatch_handover!(state, topology, sessions,
                                                 2, 3, 1, 2, 1, 2, 1, 1)
        @test state.sigma_5g_n2 == 1150
        @test state.sigma_rupa_inter == 200           # flat renumber (was wrongly 400)
        @test state.handover_count == 2
    end
end
