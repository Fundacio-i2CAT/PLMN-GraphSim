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

    @testset "step_position" begin
        loc = GeoPoint(40.0, -3.7)

        # NoMobility is a no-op.
        state = MobilityState(loc, 0.0, 0.0, 0.0, 0.0)
        @test Simulation.step_position(NoMobility(), loc, state, 10.0) === loc

        # RandomWaypoint stays within the configured per-step bound.
        m = RandomWaypoint(5.0, 0.0, 1.0)  # 5 km/h, 1 km cap per jump
        # 10 simulation seconds at 5 km/h => ~13.9 m, well under 1 km cap.
        state = MobilityState(loc, 0.0, 0.0, 0.0, 0.0)
        new_loc = Simulation.step_position(m, loc, state, 10.0)
        d_km = Types.haversine_distance(loc, new_loc)
        @test d_km <= 5.0 / 3600.0 * 10.0 + 1e-6

        # With a long dt the cap kicks in.
        state = MobilityState(loc, 0.0, 0.0, 0.0, 0.0)
        new_loc2 = Simulation.step_position(m, loc, state, 100_000.0)
        d_km2 = Types.haversine_distance(loc, new_loc2)
        @test d_km2 <= m.max_jump_km + 1e-6
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
        @test state.sigma_5g_n2 == 1080

        # Same-UPF call is a no-op.
        Simulation.handle_handover_5g!(state, topology, new_sessions, 2, 2, 2, 2, 1, 1)
        @test state.sigma_5g_n2 == 1080
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

        @test state.sigma_rupa_intra == 0
        Simulation.handle_handover_6grupa!(state, topology, 1, 2, 1, 1, 1, 1)
        @test state.sigma_rupa_intra == 200
        # Same gNB -> no-op.
        Simulation.handle_handover_6grupa!(state, topology, 2, 2, 1, 1, 1, 1)
        @test state.sigma_rupa_intra == 200
    end
end
