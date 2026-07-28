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
# moves under the UE (~7.5 km/s ground track). TS 23.501 Sec. 5.4.14.3 permits
# Xn- or N2-based handover when the serving satellite/gNB changes, so experiments
# sweep both costs against one renumber for 6G-RUPA. 5G's own NTN integration is a set of
# per-tier anchor special cases (TS 23.501 §5.43.x) — the motivation exhibit.

using SatelliteToolboxTle: read_tles, tle_epoch
using SatelliteToolboxSgp4: sgp4_init, sgp4!
using SatelliteToolboxTransformations: jd_to_gmst, ecef_to_geodetic

const EARTH_RADIUS_KM = 6371.0
# Satellite switch sensitivity: TS 23.501 Sec. 5.4.14.3 permits Xn/N2 handover.
const SIGMA_NTN_HO_5G_XN = 600
const SIGMA_NTN_HO_5G_N2 = 1150
const SIGMA_NTN_HO_5G = SIGMA_NTN_HO_5G_N2
const SIGMA_NTN_HO_RUPA = 200
const NTN_SPATIAL_BIN_DEG = 5.0

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
    handover_semantics::Symbol
    snapshot_interval_sec::Float64
    propagators::Vector{Any}
    jd0::Float64                 # TLE epoch (all LEOPath sets share one epoch)
    cache_t::Float64             # sim time (s) the cache holds; -1 = empty
    cache_lat::Vector{Float64}   # deg
    cache_lon::Vector{Float64}   # deg
    cache_alt::Vector{Float64}   # km
    spatial_bins::Dict{Tuple{Int,Int},Vector{Int}}
    member_layer_id::Int
    node_ids::Vector{Int}
    layer_stack::Any
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
                            handover_semantics::Symbol = :n2,
                            snapshot_interval_sec::Float64 = 1.0,
                            name::String = basename(tle_path))
    handover_semantics in (:xn, :n2) ||
        throw(ArgumentError("handover_semantics must be :xn or :n2"))
    snapshot_interval_sec > 0 ||
        throw(ArgumentError("snapshot_interval_sec must be positive"))
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
                         handover_semantics, snapshot_interval_sec,
                         props, tle_epoch(tles[1]), -1.0,
                         zeros(n), zeros(n), zeros(n),
                         Dict{Tuple{Int,Int},Vector{Int}}(), 0, Int[], nothing)
end

_lat_bin(lat::Float64) = clamp(floor(Int, (lat + 90.0) / NTN_SPATIAL_BIN_DEG), 0, 35)
_lon_bin(lon::Float64) = mod(floor(Int, mod(lon + 180.0, 360.0) / NTN_SPATIAL_BIN_DEG), 72)

"""
    positions_at!(c, t_sec)

Propagate every satellite to the snapshot containing `t_sec` (seconds past the
TLE epoch) and cache sub-satellite geodetic points. Quantized snapshots let
asynchronously started agents share propagation work while bounding position age.
TEME→ECEF uses the GMST rotation only — sufficient for footprint geometry (the
polar-motion correction is metres; the footprint radius is ~10³ km).
"""
function positions_at!(c::Constellation, t_sec::Float64)
    snapshot_t = floor(t_sec / c.snapshot_interval_sec) * c.snapshot_interval_sec
    c.cache_t == snapshot_t && return c
    gmst = jd_to_gmst(c.jd0 + snapshot_t / 86400)
    cg, sg = cos(gmst), sin(gmst)
    empty!(c.spatial_bins)
    for i in eachindex(c.propagators)
        r, _ = sgp4!(c.propagators[i], snapshot_t / 60) # SGP4 wants minutes; r in km TEME
        x = cg * r[1] + sg * r[2]
        y = -sg * r[1] + cg * r[2]
        lat, lon, alt = ecef_to_geodetic([x, y, r[3]] .* 1000)
        c.cache_lat[i] = rad2deg(lat)
        c.cache_lon[i] = rad2deg(lon)
        c.cache_alt[i] = alt / 1000
        push!(get!(c.spatial_bins,
                   (_lat_bin(c.cache_lat[i]), _lon_bin(c.cache_lon[i])), Int[]), i)
        if c.layer_stack !== nothing && i <= length(c.node_ids)
            c.layer_stack.node_locations[c.node_ids[i]] =
                GeoPoint(c.cache_lat[i], c.cache_lon[i])
        end
    end
    c.cache_t = snapshot_t
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
no satellite qualifies. A shell- and elevation-derived spatial window avoids a
fixed LEO-only cutoff silently excluding higher constellations.
"""
function best_satellite(c::Constellation, user::GeoPoint)
    best, best_el = 0, c.min_elevation_deg
    isempty(c.cache_alt) && return (best, 0.0)
    max_alt = maximum(c.cache_alt)
    min_el = deg2rad(c.min_elevation_deg)
    gamma = acos(EARTH_RADIUS_KM / (EARTH_RADIUS_KM + max_alt) * cos(min_el)) - min_el
    gamma_deg = rad2deg(gamma)
    lon_span = abs(user.lat) + gamma_deg >= 90.0 ? 180.0 :
        rad2deg(asin(clamp(sin(gamma) / cosd(user.lat), -1.0, 1.0)))
    first_lat_bin = _lat_bin(max(-90.0, user.lat - gamma_deg))
    last_lat_bin = _lat_bin(min(90.0, user.lat + gamma_deg))
    first_lon_bin = floor(Int, (user.lon - lon_span + 180.0) / NTN_SPATIAL_BIN_DEG)
    last_lon_bin = floor(Int, (user.lon + lon_span + 180.0) / NTN_SPATIAL_BIN_DEG)
    for lat_bin in first_lat_bin:last_lat_bin,
        raw_lon_bin in first_lon_bin:last_lon_bin
        for i in get(c.spatial_bins, (lat_bin, mod(raw_lon_bin, 72)), Int[])
            sat_el = elevation_deg(user, c.cache_lat[i], c.cache_lon[i], c.cache_alt[i])
            if sat_el >= best_el
                best, best_el = i, sat_el
            end
        end
    end
    return best, best == 0 ? 0.0 : best_el
end

"""
    install_ntn_member!(sim_state, topology, constellation; upper_layer_name=nothing)

Install the constellation as a live member of the graph-of-graphs. If no stack is
present, build the flat member/internetwork stack first. Every satellite is one
domain inside the NTN member; one enrollment attaches that member to the selected
root federation layer.
"""
function install_ntn_member!(sim_state::SimGlobalState, topology::NetworkTopology,
                             c::Constellation;
                             upper_layer_name::Union{Nothing,String} = nothing)
    stack = sim_state.layer_stack === nothing ? build_layer_stack(topology) :
            sim_state.layer_stack::LayerStack
    haskey(stack.member_of, c.operator_id) &&
        throw(ArgumentError("operator id $(c.operator_id) already has a member layer"))
    roots = [l for l in stack.layers if l.level > 0 && isempty(stack.parents[l.id])]
    upper = if upper_layer_name === nothing
        isempty(roots) && error("NTN member needs a federation layer")
        sort(roots; by = l -> (l.level, l.id))[end]
    else
        layer_by_name(stack, upper_layer_name)
    end

    positions_at!(c, 0.0)
    first_node = isempty(stack.node_locations) ? 1 : maximum(keys(stack.node_locations)) + 1
    nodes = collect(first_node:(first_node + n_satellites(c) - 1))
    locations = [GeoPoint(c.cache_lat[i], c.cache_lon[i]) for i in eachindex(nodes)]
    member = add_member_layer!(stack, nodes; name = "ntn-$(c.name)", locations = locations)
    enroll!(stack, upper.id, member)
    stack.member_of[c.operator_id] = member
    c.member_layer_id = member
    c.node_ids = nodes
    c.layer_stack = stack
    sim_state.layer_stack = stack
    sim_state.ntn = c
    return member
end

"Attachment to a satellite domain in an installed NTN member layer."
function ntn_attachment(c::Constellation, sat_index::Int)
    c.member_layer_id != 0 || error("constellation is not installed in a layer stack")
    1 <= sat_index <= length(c.node_ids) || throw(BoundsError(c.node_ids, sat_index))
    return Attachment(c.member_layer_id, c.node_ids[sat_index])
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
    charge_ntn_sat_handover!(sim_state; semantics=:n2)

Satellite-to-satellite switch inside the constellation: the network moved under
the UE. 5G sensitivity: Xn or N2 handover (TS 23.501 Sec. 5.4.14.3);
6G-RUPA: one renumber.
"""
function charge_ntn_sat_handover!(sim_state::SimGlobalState;
                                   semantics::Symbol = :n2)
    semantics in (:xn, :n2) || throw(ArgumentError("semantics must be :xn or :n2"))
    sim_state.ntn_sat_handovers += 1
    sim_state.sigma_ntn_ho_5g += semantics == :xn ? SIGMA_NTN_HO_5G_XN : SIGMA_NTN_HO_5G_N2
    sim_state.sigma_ntn_ho_rupa += SIGMA_NTN_HO_RUPA
    return sim_state
end

"""
    dispatch_ntn_move!(sim_state, constellation, old, new; num_sessions=1)

Classify a live NTN service change through the same layer DAG used by terrestrial
and federation moves, record its climb, then charge the dedicated NTN reporting
bucket. The generic classifier distinguishes member crossings from switches within
the satellite member.
"""
function dispatch_ntn_move!(sim_state::SimGlobalState, c::Constellation,
                            old::Attachment, new::Attachment;
                            num_sessions::Int = 1)
    stack = sim_state.layer_stack::LayerStack
    r = observe_move!(sim_state, stack, old, new)
    if r.class == :crossing
        charge_ntn_crossing!(sim_state, num_sessions)
    elseif r.class == :inter
        charge_ntn_sat_handover!(sim_state; semantics = c.handover_semantics)
    else
        throw(ArgumentError("NTN service change classified as $(r.class)"))
    end
    sim_state.handover_count += 1
    sim_state.core_writes_5g += Int64(num_sessions) * Int64(sim_state.config.scale_factor)
    return r
end
