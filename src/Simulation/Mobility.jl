using Random
using ..Types

"""
    step_position(model::MobilityModel, loc, dt)

Compute the next position of an agent currently at `loc` after `dt` simulation
time units, under mobility model `model`. `dt` is in the same units as the
simulator's time axis (assumed seconds; speeds in km/h are converted).

Returns a `GeoPoint`. For `NoMobility` the location is returned unchanged.
"""
function step_position(::NoMobility, loc::GeoPoint, ::Real)
    return loc
end

# Local equirectangular conversions: at the small scales of a single waypoint
# step (a few hundred metres to a few km) this is accurate to well within a
# percent and avoids the cost of full geodesic math inside a tight inner loop.
const _METERS_PER_DEG_LAT = 111_132.0

function _km_to_deg_offsets(dx_km::Float64, dy_km::Float64, ref_lat::Float64)
    lat_offset = (dy_km * 1000.0) / _METERS_PER_DEG_LAT
    lon_offset = (dx_km * 1000.0) / (_METERS_PER_DEG_LAT * cos(deg2rad(ref_lat)))
    return lat_offset, lon_offset
end

function step_position(m::RandomWaypoint, loc::GeoPoint, dt::Real)
    # Pick a random direction and a random distance bounded by what the agent
    # can walk in `dt` seconds at the configured speed. This is a per-tick
    # approximation of full Random Waypoint (no explicit waypoint memory) that
    # is sufficient for the PoC: it produces realistic cell-change rates and
    # exercises the handover path. Phase 1 will switch to a stateful version
    # with explicit destinations and pause times.
    speed_kms = m.speed_kmh / 3600.0   # km per simulation second
    max_step_km = min(speed_kms * dt, m.max_jump_km)
    if max_step_km <= 0.0
        return loc
    end
    theta = 2 * pi * rand()
    r_km = max_step_km * sqrt(rand())  # uniform in disk
    dx_km = r_km * cos(theta)
    dy_km = r_km * sin(theta)
    dlat, dlon = _km_to_deg_offsets(dx_km, dy_km, loc.lat)
    return GeoPoint(loc.lat + dlat, loc.lon + dlon)
end
