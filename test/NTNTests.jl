using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.Types

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
        Simulation.positions_at!(c, 0.0)
        @test c.cache_lat[1] == lat0
        Simulation.positions_at!(c, 300.0)
        @test c.cache_lat[1] != lat0
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
        @test s.sigma_ntn_cross_5g == 3250
        @test s.sigma_ntn_cross_rupa == 450
        @test s.ntn_session_breaks_5g == 2 * scale
        @test s.sigma_roam_5g == 0                    # §7.4 counters untouched
        @test s.roam_entries == 0

        s2 = SimGlobalState(mkcfg(:ideal_ho), [SessionContext5G[]],
                            [ForwardingEntry6GRUPA[]], [ForwardingEntry6GRUPA[]],
                            Float64[], Vector{Float64}[], Vector{Int}[],
                            Vector{Float64}[], Vector{Int}[])
        Simulation.charge_ntn_crossing!(s2, 2)
        @test s2.sigma_ntn_cross_5g == 1300           # idealized inter-op HO
        @test s2.ntn_session_breaks_5g == 0           # no break in ideal semantics

        # Satellite→satellite switch within the constellation: NG-RAN node change
        # (NR satellite is a RAT of the 5GS, TS 23.501 §5.4.10) → N2-class σ;
        # RUPA: one renumber.
        Simulation.charge_ntn_sat_handover!(s)
        @test s.ntn_sat_handovers == 1
        @test s.sigma_ntn_ho_5g == 1150
        @test s.sigma_ntn_ho_rupa == 200
    end
end
