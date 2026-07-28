using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.Types
using DesJulia6gRupa.DataLoading
using ConcurrentSim: ConcurrentSim, Process, @process
using Random

if !isdefined(Main, :TestFixtures)
    include("TestFixtures.jl")
end
using .TestFixtures

# NTN escalation (§7.5.2): a satellite constellation is one more federation member.
# Orbital inputs are the SAME TLE files LEOPath uses (data/ntn/, from the published
# NTN paper's simulator); propagation here is SGP4 via SatelliteToolboxSgp4.
# Cross-validation fixtures below were generated with LEOPath's propagator (pyephem,
# same TLEs, epoch 2000-01-01 00:00 UTC). Longitudes agree to <0.01°; latitudes to
# <0.2° (geodetic vs geocentric sub-latitude convention), both ≪ the ~940 km
# footprint radius that drives attachment.

const TLE_STARLINK = joinpath(pkgdir(DesJulia6gRupa), "data", "ntn",
                              "tles_starlink_550_sgp.txt")

@testset "NTN constellation (§7.5.2)" begin

    @testset "load_constellation parses the LEOPath TLE set" begin
        c = Simulation.load_constellation(TLE_STARLINK; operator_id = 9,
                                          min_elevation_deg = 25.0, r_terr_km = 30.0)
        @test Simulation.n_satellites(c) == 1584
        @test c.operator_id == 9
        @test c.min_elevation_deg == 25.0
        @test c.r_terr_km == 30.0
    end

    @testset "cross-validation against LEOPath (pyephem, same TLEs)" begin
        c = Simulation.load_constellation(TLE_STARLINK; operator_id = 9)
        # (sat index 1-based, t seconds, pyephem sublat, pyephem sublong)
        fixtures = [
            (1,    0.0,   -0.079, -100.027),
            (1,  300.0,   14.994,  -89.585),
            (1,  600.0,   29.387,  -77.376),
            (500,   0.0, -19.792,  -17.531),
            (500, 300.0,  -4.868,   -6.738),
            (500, 600.0,  10.269,    3.528),
            (1200,  0.0, -40.884,   22.606),
            (1200,300.0, -50.140,   45.156),
            (1200,600.0, -52.877,   74.271),
        ]
        for (i, t, lat, lon) in fixtures
            Simulation.positions_at!(c, t)
            @test abs(c.cache_lat[i] - lat) < 0.2      # geodetic-vs-geocentric
            @test abs(c.cache_lon[i] - lon) < 0.06
            @test 480.0 < c.cache_alt[i] < 580.0       # ~550 km shell
        end
    end

    @testset "elevation geometry" begin
        user = GeoPoint(40.0, -4.0)
        # Satellite directly overhead → ~90°.
        @test Simulation.elevation_deg(user, 40.0, -4.0, 550.0) > 89.0
        # At the 25°-elevation footprint edge for a 550 km shell the ground
        # distance is ≈ 930 km; check the elevation crosses 25° there.
        el_inside  = Simulation.elevation_deg(user, 40.0 + 7.0, -4.0, 550.0) # ~780 km
        el_outside = Simulation.elevation_deg(user, 40.0 + 10.0, -4.0, 550.0) # ~1110 km
        @test el_inside > 25.0 > el_outside
        # Monotone: farther → lower.
        @test el_inside > el_outside
    end

    @testset "best_satellite over Iberia" begin
        c = Simulation.load_constellation(TLE_STARLINK; operator_id = 9,
                                          min_elevation_deg = 25.0)
        Simulation.positions_at!(c, 0.0)
        madrid = GeoPoint(40.4, -3.7)
        sat, el = Simulation.best_satellite(c, madrid)
        @test sat != 0                     # 1584-sat shell always covers Iberia
        @test el >= 25.0
        # Impossibly high elevation floor → no satellite qualifies.
        c99 = Simulation.load_constellation(TLE_STARLINK; operator_id = 9,
                                            min_elevation_deg = 89.999)
        Simulation.positions_at!(c99, 0.0)
        sat99, _ = Simulation.best_satellite(c99, madrid)
        @test sat99 == 0
    end

    @testset "position cache: same t reuses, new t recomputes" begin
        c = Simulation.load_constellation(TLE_STARLINK; operator_id = 9)
        Simulation.positions_at!(c, 0.0)
        lat0 = c.cache_lat[1]
        Simulation.positions_at!(c, 0.9)
        @test c.cache_lat[1] == lat0
        @test c.cache_t == 0.0
        Simulation.positions_at!(c, 1.1)
        @test c.cache_lat[1] != lat0
        @test c.cache_t == 1.0
    end

    @testset "NTN charge functions: crossing + intra-constellation handover" begin
        scale = 1000
        mkcfg(sem) = SimConfig(1, 1, scale, 10.0, 5.0, 5.0, :two_tier, 1, 1.0,
                               MobilityConfig(), RoamingConfig(sem, 0.0))
        # Terrestrial↔NTN crossing follows B7a semantics like any member crossing,
        # but is counted in its own bucket (does not pollute §7.4 roam counters).
        s = SimGlobalState(mkcfg(:reestablish), [SessionContext5G[]],
                           [ForwardingEntry6GRUPA[]], [ForwardingEntry6GRUPA[]],
                           Float64[], Vector{Float64}[], Vector{Int}[],
                           Vector{Float64}[], Vector{Int}[])
        Simulation.charge_ntn_crossing!(s, 2)
        @test s.sigma_ntn_cross_5g == SIGMA_ROAM_5G_REEST
        @test s.sigma_ntn_cross_rupa == SIGMA_ROAM_RUPA
        @test s.ntn_session_breaks_5g == 2 * scale
        @test s.sigma_roam_5g == 0                    # §7.4 counters untouched
        @test s.roam_entries == 0

        s2 = SimGlobalState(mkcfg(:ideal_ho), [SessionContext5G[]],
                            [ForwardingEntry6GRUPA[]], [ForwardingEntry6GRUPA[]],
                            Float64[], Vector{Float64}[], Vector{Int}[],
                            Vector{Float64}[], Vector{Int}[])
        Simulation.charge_ntn_crossing!(s2, 2)
        @test s2.sigma_ntn_cross_5g == SIGMA_ROAM_5G_IDEAL           # idealized inter-op HO
        @test s2.ntn_session_breaks_5g == 0           # no break in ideal semantics

        # Satellite→satellite switch within the constellation: NG-RAN node change
        # (NR satellite is a RAT of the 5GS, TS 23.501 §5.4.10) → N2-class σ;
        # RUPA: one renumber.
        Simulation.charge_ntn_sat_handover!(s)
        @test s.ntn_sat_handovers == 1
        @test s.sigma_ntn_ho_5g == SIGMA_NTN_SATHO_5G
        @test s.sigma_ntn_ho_rupa == SIGMA_NTN_SATHO_RUPA

        Simulation.charge_ntn_sat_handover!(s2; semantics = :xn)
        @test s2.sigma_ntn_ho_5g == SIGMA_XN
        @test_throws ArgumentError Simulation.charge_ntn_sat_handover!(s2; semantics = :invalid)
    end

    @testset "live NTN member uses graph-of-graphs classification" begin
        topology = DataLoading.compose_topologies([
            op_field(2, -4.0, 1000, "a"),
            op_field(2, -7.0, 1000, "b"),
        ])
        config = SimConfig(1, 1, 10, 20.0, 10.0, 0.001, :two_tier, 2, 1.0,
                           MobilityConfig(true, 1.0, NoMobility()),
                           RoamingConfig(:reestablish, 0.0))
        state = Simulation.init_global_state_for_simulation(topology, config)
        c = Simulation.load_constellation(TLE_STARLINK; operator_id = 9,
                                          r_terr_km = 0.0,
                                          handover_semantics = :n2)
        member = Simulation.install_ntn_member!(state, topology, c)
        @test state.ntn === c
        @test c.member_layer_id == member
        @test state.layer_stack.member_of[9] == member

        terrestrial = Simulation.attachment_of(state.layer_stack, topology, 1)
        satellite_1 = Simulation.ntn_attachment(c, 1)
        satellite_2 = Simulation.ntn_attachment(c, 2)
        crossing = Simulation.dispatch_ntn_move!(state, c, terrestrial, satellite_1)
        @test crossing.class == :crossing && crossing.climb == 1
        @test state.ho_climb == [1]
        internal = Simulation.dispatch_ntn_move!(state, c, satellite_1, satellite_2)
        @test internal.class == :inter && internal.climb == 0
        @test state.ntn_sat_handovers == 1
        @test state.handover_count == 2
        @test state.core_writes_5g == 2 * config.scale_factor

        c.operator_id = 1
        @test_throws ArgumentError Simulation.install_ntn_member!(state, topology, c)
    end

    @testset "live lifecycle distinguishes satellite service from outage" begin
        function run_one(min_elevation; recover_to = nothing)
            topology = DataLoading.compose_topologies([
                op_field(2, -4.0, 1000, "a"),
                op_field(2, -7.0, 1000, "b"),
            ])
            config = SimConfig(1, 1, 1, 6.0, 10.0, 0.001, :two_tier, 2, 1.0,
                               MobilityConfig(true, 1.0, NoMobility()),
                               RoamingConfig(:reestablish, 0.0))
            state = Simulation.init_global_state_for_simulation(topology, config)
            c = Simulation.load_constellation(TLE_STARLINK; operator_id = 9,
                                              min_elevation_deg = min_elevation,
                                              r_terr_km = 0.0)
            Simulation.install_ntn_member!(state, topology, c)
            Random.seed!(42)
            env = ConcurrentSim.Simulation()
            @process Simulation.user_lifecycle(env, 1, state, topology, eMBB)
            if recover_to !== nothing
                ConcurrentSim.run(env, 3.0)
                if recover_to == :terrestrial
                    c.r_terr_km = Inf
                elseif recover_to == :satellite
                    c.min_elevation_deg = 25.0
                else
                    error("unknown recovery target $recover_to")
                end
            end
            ConcurrentSim.run(env, config.duration)
            return state, topology
        end

        served, served_topology = run_one(25.0)
        @test served.ntn_attach_events == 1
        @test served.ntn_serving_ticks > 0
        @test served.ntn_outage_ticks == 0
        @test sum(served.ho_climb; init = 0) == served.ntn_attach_events + served.ntn_return_events
        @test all(!haskey(served_topology.graph, (:Agent, 1), (:gNB, g))
                  for g in eachindex(served_topology.gnb_locations))

        outage, _ = run_one(91.0)
        @test outage.ntn_attach_events == 0
        @test outage.ntn_return_events == 0
        @test outage.ntn_serving_ticks == 0
        @test outage.ntn_outage_ticks > 0

        recovered, recovered_topology = run_one(91.0; recover_to = :terrestrial)
        @test recovered.ntn_outage_ticks > 0
        @test recovered.handover_count == 0
        @test recovered.core_writes_5g == 1
        @test any(haskey(recovered_topology.graph, (:Agent, 1), (:gNB, g))
                  for g in eachindex(recovered_topology.gnb_locations))

        recovered_sat, recovered_sat_topology = run_one(91.0; recover_to = :satellite)
        @test recovered_sat.ntn_outage_ticks > 0
        @test recovered_sat.ntn_serving_ticks > 0
        @test recovered_sat.handover_count == 0
        @test recovered_sat.core_writes_5g == 1
        @test all(!haskey(recovered_sat_topology.graph, (:Agent, 1), (:gNB, g))
                  for g in eachindex(recovered_sat_topology.gnb_locations))
    end
end
