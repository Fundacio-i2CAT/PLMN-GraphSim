using Random
using ..Types

"""
    step_position(model::MobilityModel, loc::GeoPoint, state::MobilityState, dt::Real)

Compute next position of agent at `loc` after `dt` time, using mobility `model`.
Updates `state` in-place (waypoint, pause countdown, velocity).
Returns new `GeoPoint`.

For stateless models (NoMobility), state is ignored.
"""
function step_position(::NoMobility, loc::GeoPoint, ::MobilityState, ::Real)
    return loc
end

const _METERS_PER_DEG_LAT = 111_132.0

function _km_to_deg_offsets(dx_km::Float64, dy_km::Float64, ref_lat::Float64)
    lat_offset = (dy_km * 1000.0) / _METERS_PER_DEG_LAT
    lon_offset = (dx_km * 1000.0) / (_METERS_PER_DEG_LAT * cos(deg2rad(ref_lat)))
    return lat_offset, lon_offset
end

"""
    step_position(m::RandomWaypoint, loc::GeoPoint, state::MobilityState, dt::Real)

Stateful Random Waypoint: agent moves toward waypoint at configured speed,
pauses at waypoint, then picks new waypoint. Explicit destination tracking.
"""
function step_position(m::RandomWaypoint, loc::GeoPoint, state::MobilityState, dt::Real)
    speed_kms = m.speed_kmh / 3600.0  # km per simulation second

    # If in pause, decrement pause timer
    if state.pause_countdown > 0.0
        state.pause_countdown -= dt
        if state.pause_countdown <= 0.0
            # Pause ended, pick new waypoint
            state.pause_countdown = m.pause_time
            theta = 2 * pi * rand()
            r_km = m.max_jump_km * sqrt(rand())
            dx_km = r_km * cos(theta)
            dy_km = r_km * sin(theta)
            dlat, dlon = _km_to_deg_offsets(dx_km, dy_km, loc.lat)
            state.current_waypoint = GeoPoint(loc.lat + dlat, loc.lon + dlon)
            state.time_to_arrival = sqrt((dlat * _METERS_PER_DEG_LAT)^2 +
                                          (dlon * _METERS_PER_DEG_LAT * cos(deg2rad(loc.lat)))^2) / 1000.0 / speed_kms
        end
        return loc  # Stay put during pause
    end

    # Moving toward waypoint
    if state.time_to_arrival <= 0.0
        # Already at waypoint, enter pause
        state.pause_countdown = m.pause_time
        return loc
    end

    # Move toward waypoint
    dist_available_km = speed_kms * dt
    dlat_to_wp = state.current_waypoint.lat - loc.lat
    dlon_to_wp = state.current_waypoint.lon - loc.lon
    dist_to_wp_deg_sq = dlat_to_wp^2 + dlon_to_wp^2

    if dist_to_wp_deg_sq == 0.0
        state.time_to_arrival = 0.0
        return loc
    end

    dist_to_wp_m = sqrt((dlat_to_wp * _METERS_PER_DEG_LAT)^2 +
                        (dlon_to_wp * _METERS_PER_DEG_LAT * cos(deg2rad(loc.lat)))^2)
    dist_to_wp_km = dist_to_wp_m / 1000.0

    if dist_available_km >= dist_to_wp_km
        # Reach waypoint this step
        state.time_to_arrival = 0.0
        return state.current_waypoint
    end

    # Move partway toward waypoint
    frac = dist_available_km / dist_to_wp_km
    state.time_to_arrival -= dt
    new_lat = loc.lat + frac * dlat_to_wp
    new_lon = loc.lon + frac * dlon_to_wp
    return GeoPoint(new_lat, new_lon)
end

"""
    step_position(m::GaussMarkov, loc::GeoPoint, state::MobilityState, dt::Real)

Gauss-Markov mobility: velocity autocorrelates with parameter alpha.
Smoother than Random Waypoint, avoids sharp turns and speed decay.
"""
function step_position(m::GaussMarkov, loc::GeoPoint, state::MobilityState, dt::Real)
    speed_kms = m.speed_kmh / 3600.0  # km per simulation second
    max_accel_kms2 = m.max_acceleration / 1000.0  # km/s^2

    # Update velocity with autocorrelation and acceleration bounds
    accel_x = (2 * rand() - 1) * max_accel_kms2 * dt
    accel_y = (2 * rand() - 1) * max_accel_kms2 * dt

    state.velocity_x = m.alpha * state.velocity_x + (1 - m.alpha) * (rand() * speed_kms - speed_kms/2) + accel_x * dt
    state.velocity_y = m.alpha * state.velocity_y + (1 - m.alpha) * (rand() * speed_kms - speed_kms/2) + accel_y * dt

    # Clamp total speed to max
    current_speed = sqrt(state.velocity_x^2 + state.velocity_y^2)
    if current_speed > speed_kms
        scale = speed_kms / current_speed
        state.velocity_x *= scale
        state.velocity_y *= scale
    end

    # Apply displacement
    dx_km = state.velocity_x * dt
    dy_km = state.velocity_y * dt
    dlat, dlon = _km_to_deg_offsets(dx_km, dy_km, loc.lat)

    return GeoPoint(loc.lat + dlat, loc.lon + dlon)
end
