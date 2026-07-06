# NTN escalation (§7.5.2): a satellite constellation as one more federation member.
#
# Orbital inputs are the SAME TLE files LEOPath uses (data/ntn/, published NTN-paper
# simulator); propagation is SGP4 (SatelliteToolboxSgp4), cross-validated against
# LEOPath's pyephem propagator in test/NTNTests.jl. The sim needs only sub-satellite
# points vs time: attachment is a min-elevation cone around the sub-satellite point.
#
# Scenario semantics (runs/ntn.jl): a UE whose nearest terrestrial gNB is farther
# than `r_terr_km` has no terrestrial signal and roams to the satellite member —
# a terrestrial↔NTN crossing, charged with the same B7a semantics as any member
# crossing but counted in its own bucket. While satellite-served, the *network*
# moves under the UE (~7.5 km/s ground track): satellite switches are NG-RAN node
# changes (NR satellite access is a RAT of the 5GS, TS 23.501 §5.4.10) → N2-class
# σ for 5G vs one renumber for 6G-RUPA. 5G's own NTN integration is a set of
# per-tier anchor special cases (TS 23.501 §5.43.x) — the motivation exhibit.

using SatelliteToolboxTle: read_tles, tle_epoch
using SatelliteToolboxSgp4: sgp4_init, sgp4!
using SatelliteToolboxTransformations: jd_to_gmst, ecef_to_geodetic

const EARTH_RADIUS_KM = 6371.0
# Satellite→satellite switch = NG-RAN node change with the anchor preserved on the
# ground (feeder link) → N2 class (mobility-formal-model.md L2); RUPA renumber flat.
const SIGMA_NTN_HO_5G = 1150
const SIGMA_NTN_HO_RUPA = 200

"""
A satellite constellation acting as a federation member. Holds initialized SGP4
propagators plus a per-timestep cache of sub-satellite points (all agents in a
tick share one propagation pass). `r_terr_km` is the scenario's terrestrial
coverage threshold: beyond it the UE attaches to this member.
"""
mutable struct Constellation
    name::String
    operator_id::Int
    min_elevation_deg::Float64
    r_terr_km::Float64
    propagators::Vector{Any}
    jd0::Float64                 # TLE epoch (all LEOPath sets share one epoch)
    cache_t::Float64             # sim time (s) the cache holds; -1 = empty
    cache_lat::Vector{Float64}   # deg
    cache_lon::Vector{Float64}   # deg
    cache_alt::Vector{Float64}   # km
end

n_satellites(c::Constellation) = length(c.propagators)

"""
    load_constellation(tle_path; operator_id, min_elevation_deg=25.0, r_terr_km=30.0)

Parse a LEOPath TLE file (optional `P S` count header line is skipped) and
initialize one SGP4 propagator per satellite.
"""
function load_constellation(tle_path::String; operator_id::Int,
                            min_elevation_deg::Float64 = 25.0,
                            r_terr_km::Float64 = 30.0,
                            name::String = basename(tle_path))
    lines = readlines(tle_path)
    # LEOPath files start with "<planes> <sats_per_plane>"; TLE content starts at
    # a name line or a "1 " line.
    first_tokens = split(strip(lines[1]))
    header = length(first_tokens) == 2 && all(t -> tryparse(Int, t) !== nothing, first_tokens)
    body = join(header ? lines[2:end] : lines, "\n")
    tles = read_tles(body)
    isempty(tles) && error("no TLEs parsed from $tle_path")
    props = Any[sgp4_init(t) for t in tles]
    n = length(props)
    return Constellation(name, operator_id, min_elevation_deg, r_terr_km,
                         props, tle_epoch(tles[1]), -1.0,
                         zeros(n), zeros(n), zeros(n))
end

"""
    positions_at!(c, t_sec)

Propagate every satellite to sim time `t_sec` (seconds past the TLE epoch) and
cache sub-satellite geodetic points. No-op when the cache already holds `t_sec`.
TEME→ECEF uses the GMST rotation only — sufficient for footprint geometry (the
polar-motion correction is metres; the footprint radius is ~10³ km).
"""
function positions_at!(c::Constellation, t_sec::Float64)
    c.cache_t == t_sec && return c
    gmst = jd_to_gmst(c.jd0 + t_sec / 86400)
    cg, sg = cos(gmst), sin(gmst)
    for i in eachindex(c.propagators)
        r, _ = sgp4!(c.propagators[i], t_sec / 60)   # SGP4 wants minutes; r in km TEME
        x = cg * r[1] + sg * r[2]
        y = -sg * r[1] + cg * r[2]
        lat, lon, alt = ecef_to_geodetic([x, y, r[3]] .* 1000)
        c.cache_lat[i] = rad2deg(lat)
        c.cache_lon[i] = rad2deg(lon)
        c.cache_alt[i] = alt / 1000
    end
    c.cache_t = t_sec
    return c
end

"""
    elevation_deg(user, sat_lat, sat_lon, sat_alt_km) -> Float64

Elevation angle of a satellite as seen from a ground point, from the central
angle γ between the ground point and the sub-satellite point:
`el = atan(cos γ − R/(R+h), sin γ)`.
"""
function elevation_deg(user::GeoPoint, sat_lat::Float64, sat_lon::Float64,
                       sat_alt_km::Float64)
    γ = haversine_distance(user, GeoPoint(sat_lat, sat_lon)) / EARTH_RADIUS_KM
    return rad2deg(atan(cos(γ) - EARTH_RADIUS_KM / (EARTH_RADIUS_KM + sat_alt_km),
                        sin(γ)))
end

"""
    best_satellite(c, user) -> (sat_index, elevation_deg)

Highest-elevation satellite above `c.min_elevation_deg` for a ground point, using
the current position cache (call `positions_at!` first). Returns `(0, 0.0)` when
no satellite qualifies. A coarse latitude/longitude window (~12°) skips satellites
that cannot be above the horizon-elevation floor of any LEO shell.
"""
function best_satellite(c::Constellation, user::GeoPoint)
    best, best_el = 0, c.min_elevation_deg
    for i in eachindex(c.cache_lat)
        abs(c.cache_lat[i] - user.lat) > 12.0 && continue
        dlon = abs(c.cache_lon[i] - user.lon)
        dlon > 180.0 && (dlon = 360.0 - dlon)
        dlon * cosd(user.lat) > 12.0 && continue
        el = elevation_deg(user, c.cache_lat[i], c.cache_lon[i], c.cache_alt[i])
        if el >= best_el
            best, best_el = i, el
        end
    end
    return best, best == 0 ? 0.0 : best_el
end

"""
    charge_ntn_crossing!(sim_state, num_sessions)

Terrestrial↔NTN member crossing (either direction). Same B7a semantics switch as
a terrestrial border crossing — deployed 5G re-establishes (registration + HR PDU
session, flows break), the idealized inter-operator HO does not — but counted in
NTN-specific buckets so the §7.4 roam counters stay clean when both scenarios run.
RUPA: enrollment + renumber into the satellite member's part of the shared DIF.
"""
function charge_ntn_crossing!(sim_state::SimGlobalState, num_sessions::Int)
    if sim_state.config.roaming.border_semantics == :ideal_ho
        sim_state.sigma_ntn_cross_5g += SIGMA_ROAM_5G_IDEAL_HO
    else
        sim_state.sigma_ntn_cross_5g += SIGMA_ROAM_5G_REESTABLISH
        sim_state.ntn_session_breaks_5g +=
            Int64(num_sessions) * Int64(sim_state.config.scale_factor)
    end
    sim_state.sigma_ntn_cross_rupa += SIGMA_ROAM_RUPA_ENTRY
    return sim_state
end

"""
    charge_ntn_sat_handover!(sim_state)

Satellite→satellite switch inside the constellation: the network moved under the
UE. 5G: NG-RAN node change (N2 class, anchor preserved on the ground feeder);
6G-RUPA: one renumber.
"""
function charge_ntn_sat_handover!(sim_state::SimGlobalState)
    sim_state.ntn_sat_handovers += 1
    sim_state.sigma_ntn_ho_5g += SIGMA_NTN_HO_5G
    sim_state.sigma_ntn_ho_rupa += SIGMA_NTN_HO_RUPA
    return sim_state
end
