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

    # State 1: pausing at a waypoint. Decrement and stay put.
    # When the pause expires we fall through (no waypoint yet -> time_to_arrival<=0)
    # so a fresh route is picked on this same tick and motion resumes immediately.
    if state.pause_countdown > 0.0
        state.pause_countdown -= dt
        state.pause_countdown > 0.0 && return loc
    end

    # State 2: no active route -> pick a new waypoint and start moving this tick.
    if state.time_to_arrival <= 0.0
        theta = 2 * pi * rand()
        r_km = m.max_jump_km * sqrt(rand())          # uniform over disk
        dx_km = r_km * cos(theta)
        dy_km = r_km * sin(theta)
        dlat, dlon = _km_to_deg_offsets(dx_km, dy_km, loc.lat)
        state.current_waypoint = GeoPoint(loc.lat + dlat, loc.lon + dlon)
        state.time_to_arrival = max(r_km, 1e-9) / speed_kms
    end

    # State 3: move toward the active waypoint at constant speed.
    dlat_to_wp = state.current_waypoint.lat - loc.lat
    dlon_to_wp = state.current_waypoint.lon - loc.lon
    dist_to_wp_km = sqrt((dlat_to_wp * _METERS_PER_DEG_LAT)^2 +
                         (dlon_to_wp * _METERS_PER_DEG_LAT * cos(deg2rad(loc.lat)))^2) / 1000.0
    dist_available_km = speed_kms * dt

    if dist_to_wp_km <= 1e-9 || dist_available_km >= dist_to_wp_km
        # Reached the waypoint this tick -> snap there and begin pausing.
        state.time_to_arrival = 0.0
        state.pause_countdown = m.pause_time
        return state.current_waypoint
    end

    frac = dist_available_km / dist_to_wp_km
    state.time_to_arrival -= dt
    return GeoPoint(loc.lat + frac * dlat_to_wp, loc.lon + frac * dlon_to_wp)
end

"""
    step_position(m::GaussMarkov, loc::GeoPoint, state::MobilityState, dt::Real)

Gauss-Markov mobility: velocity autocorrelates with parameter alpha.
Smoother than Random Waypoint, avoids sharp turns and speed decay.
"""
function step_position(m::GaussMarkov, loc::GeoPoint, state::MobilityState, dt::Real)
    speed_kms = m.speed_kmh / 3600.0  # km per simulation second (mean speed μ)

    # First call: seed a persistent heading at full speed so motion is ballistic
    # (sustained directional travel), not a mean-zero diffusive random walk.
    if state.velocity_x == 0.0 && state.velocity_y == 0.0
        θ0 = 2 * pi * rand()
        state.velocity_x = speed_kms * cos(θ0)
        state.velocity_y = speed_kms * sin(θ0)
    end

    # Gauss-Markov update around mean speed μ with autocorrelation α:
    #   v_n = α v_{n-1} + (1-α) μ̂ + sqrt(1-α²) σ ξ
    # We keep the mean magnitude at μ and let the direction drift; the
    # acceleration bound caps the per-step heading/speed perturbation.
    σ = (m.max_acceleration / 1000.0) * dt      # km/s perturbation scale
    cur = sqrt(state.velocity_x^2 + state.velocity_y^2)
    cur = cur == 0.0 ? speed_kms : cur
    μx = speed_kms * state.velocity_x / cur     # mean dir = current heading, magnitude μ
    μy = speed_kms * state.velocity_y / cur
    g = sqrt(max(1 - m.alpha^2, 0.0))
    state.velocity_x = m.alpha * state.velocity_x + (1 - m.alpha) * μx + g * σ * (2 * rand() - 1)
    state.velocity_y = m.alpha * state.velocity_y + (1 - m.alpha) * μy + g * σ * (2 * rand() - 1)

    # Renormalize to mean speed μ so the agent keeps moving (no speed decay).
    spd = sqrt(state.velocity_x^2 + state.velocity_y^2)
    if spd > 0.0
        state.velocity_x *= speed_kms / spd
        state.velocity_y *= speed_kms / spd
    end

    dx_km = state.velocity_x * dt
    dy_km = state.velocity_y * dt
    dlat, dlon = _km_to_deg_offsets(dx_km, dy_km, loc.lat)
    return GeoPoint(loc.lat + dlat, loc.lon + dlon)
end
