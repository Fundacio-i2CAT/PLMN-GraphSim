module Types

using Agents
using Graphs
using MetaGraphsNext
using Distributions
using Random
using GeometryBasics

export FAR, SessionContext5G, ForwardingEntry6GRUPA, ForwardingState5G, SessionSimMetadata
export SimGlobalState, GeoPoint, NetworkTopology, GUPFState6GRUPA, Municipality, SimConfig
export haversine_distance, UserType, eMBB, mMTC, URLLC
export MobilityConfig, MobilityModel, NoMobility, RandomWaypoint, GaussMarkov, MobilityState

@enum UserType begin
    eMBB
    mMTC
    URLLC
end

struct GeoPoint
    lat::Float64
    lon::Float64
end

function haversine_distance(p1::GeoPoint, p2::GeoPoint)
    R = 6371.0 # Earth radius in km
    dlat = deg2rad(p2.lat - p1.lat)
    dlon = deg2rad(p2.lon - p1.lon)
    a = sin(dlat / 2)^2 + cos(deg2rad(p1.lat)) * cos(deg2rad(p2.lat)) * sin(dlon / 2)^2
    c = 2 * atan(sqrt(a), sqrt(1 - a))
    return R * c
end

struct Municipality
    code::String
    name::String
    population::Int
    location::GeoPoint
    area::Float64 # In hectares
    polygon::Any # GeometryBasics.Polygon or MultiPolygon or similar
end

struct FAR
    action::UInt8
    destination_ip::UInt32
end

struct ForwardingState5G
    ul_teid::UInt32
    dl_teid::UInt32
    ul_far::FAR
    dl_far::FAR
end

struct SessionSimMetadata
    serving_upf_index::Int # The UPF currently serving the gNB (UL-CL)
    anchor_upf_index::Int  # The UPF acting as PDU Session Anchor (PSA)
    domain_id::Int         # Attachment domain for inter-domain handover classification
    operator_id::Int       # Operator/layer ID for roaming scenarios (1=primary, 2+=visited/satellite)
end

struct SessionContext5G
    forwarding::ForwardingState5G
    metadata::SessionSimMetadata
end

struct ForwardingEntry6GRUPA
    dest_prefix::UInt32
    mask::UInt32
    output_interface::Int32
end

# --- Mobility Models ---
# Abstract type so future models (trajectory replay, population-aware, ...) can be added without touching lifecycle code.
abstract type MobilityModel end

"Stationary user. Equivalent to legacy behaviour (single-shot location)."
struct NoMobility <: MobilityModel end

"""
Stateful Random Waypoint mobility model.

Agents pick explicit waypoint destinations and move toward them at `speed_kmh`,
honoring `pause_time` at each waypoint before picking the next. Tracks per-agent
state: current waypoint, time-to-arrival, pause countdown.

Speeds in km/h, pause time in simulation time units (assumed seconds).
"""
struct RandomWaypoint <: MobilityModel
    speed_kmh::Float64
    pause_time::Float64
    max_jump_km::Float64
end

"""
Gauss-Markov mobility model.

Smoother than Random Waypoint. Velocity autocorrelates over time, avoiding
sharp turns and sudden speed changes. Parameter `alpha` controls correlation
(0 = independent per tick, 1 = perfectly correlated, typically 0.5-0.7).
"""
struct GaussMarkov <: MobilityModel
    speed_kmh::Float64
    alpha::Float64         # Velocity autocorrelation coefficient
    max_acceleration::Float64  # m/s^2, bounds rate of velocity change
end

# Per-agent mobility state (used by step_position to track waypoint, velocity history)
mutable struct MobilityState
    current_waypoint::GeoPoint
    time_to_arrival::Float64  # seconds until reaching waypoint (RWP)
    pause_countdown::Float64  # seconds remaining in pause (RWP)
    velocity_x::Float64       # km/h, eastward (Gauss-Markov)
    velocity_y::Float64       # km/h, northward (Gauss-Markov)
end

"""
Per-simulation mobility configuration.

`enabled = false` keeps the legacy stationary behaviour intact (default).
`update_interval` controls how often the agent re-evaluates its position and
serving gNB; smaller values give finer-grained handover detection at higher
simulation cost.
"""
struct MobilityConfig
    enabled::Bool
    update_interval::Float64
    model::MobilityModel
end

MobilityConfig() = MobilityConfig(false, 1.0, NoMobility())

struct SimConfig
    min_sessions::Int
    max_sessions::Int
    scale_factor::Int
    duration::Float64
    mean_session_duration::Float64
    mean_offline_duration::Float64
    scenario::Symbol # :basic, :two_tier, :roaming
    num_centralized_upfs::Int # For :two_tier scenario
    sampling_interval::Float64
    mobility::MobilityConfig
end

# Backward-compatible constructor (mobility disabled by default).
SimConfig(min_sessions, max_sessions, scale_factor, duration,
          mean_session_duration, mean_offline_duration, scenario,
          num_centralized_upfs, sampling_interval) =
    SimConfig(min_sessions, max_sessions, scale_factor, duration,
              mean_session_duration, mean_offline_duration, scenario,
              num_centralized_upfs, sampling_interval, MobilityConfig())

# --- Simulation State ---
mutable struct SimGlobalState
    # Config
    config::SimConfig
    upf_sessions_5g::Vector{Vector{SessionContext5G}}
    forwarding_tables_6grupa::Vector{Vector{ForwardingEntry6GRUPA}}
    centralized_forwarding_tables_6grupa::Vector{Vector{ForwardingEntry6GRUPA}} # TODO Remove

    # Metrics History
    history_time::Vector{Float64}
    history_per_upf_5g_fwd_state_info_size_mb::Vector{Vector{Float64}}
    history_per_upf_entries_5g::Vector{Vector{Int}}
    history_per_gupf_6grupa_fwd_state_info_size_mb::Vector{Vector{Float64}}
    history_per_gupf_entries_6grupa::Vector{Vector{Int}}

    # --- Mobility / Handover Counters (grounded in formal model) ---
    # Cumulative byte counts per handover procedure type (from mobility-formal-model.md).
    handover_count::Int                  # total cell-change events detected
    sigma_5g_xn::Int64                   # 5G Xn handover signaling bytes (600 B/handover)
    sigma_5g_n2::Int64                   # 5G N2 handover signaling bytes (1150 B/handover)
    sigma_rupa_intra::Int64              # 6G-RUPA intra-domain renumbering bytes (200 B/handover)
    sigma_rupa_inter::Int64              # 6G-RUPA inter-domain renumbering bytes (400 B/handover)
    sigma_roam_5g::Int64                 # 5G Home-Routed roaming bytes (1180 B/handover)
    sigma_roam_rupa::Int64               # 6G-RUPA inter-layer roaming bytes (300 B/handover)
    # Per-sampling-tick history (parallel to history_time).
    history_handovers::Vector{Int}
    history_sigma_5g_xn::Vector{Int64}
    history_sigma_5g_n2::Vector{Int64}
    history_sigma_rupa_intra::Vector{Int64}
    history_sigma_rupa_inter::Vector{Int64}
    history_sigma_roam_5g::Vector{Int64}
    history_sigma_roam_rupa::Vector{Int64}

    # --- Core forwarding-state churn under mobility (the O(n) vs O(1) headline) ---
    # Cumulative per-session forwarding-state write operations at core/UPF nodes
    # caused by handovers, scaled by scale_factor (real users). 5G: O(n); RUPA: 0.
    core_writes_5g::Int64
    core_writes_rupa::Int64
    history_core_writes_5g::Vector{Int64}
    history_core_writes_rupa::Vector{Int64}
end

# Backward-compatible constructor: all σ counters and histories initialized to 0/empty.
SimGlobalState(config, upf_sessions_5g, forwarding_tables_6grupa,
               centralized_forwarding_tables_6grupa, history_time,
               history_per_upf_5g_fwd_state_info_size_mb,
               history_per_upf_entries_5g,
               history_per_gupf_6grupa_fwd_state_info_size_mb,
               history_per_gupf_entries_6grupa) =
    SimGlobalState(config, upf_sessions_5g, forwarding_tables_6grupa,
                   centralized_forwarding_tables_6grupa, history_time,
                   history_per_upf_5g_fwd_state_info_size_mb,
                   history_per_upf_entries_5g,
                   history_per_gupf_6grupa_fwd_state_info_size_mb,
                   history_per_gupf_entries_6grupa,
                   0, Int64(0), Int64(0), Int64(0), Int64(0), Int64(0), Int64(0),
                   Int[], Int64[], Int64[], Int64[], Int64[], Int64[], Int64[],
                   Int64(0), Int64(0), Int64[], Int64[])

struct GUPFState6GRUPA
    forwarding_table::Vector{ForwardingEntry6GRUPA}
end

# --- Network Topology ---

struct NetworkTopology
    gnb_locations::Vector{GeoPoint}
    upf_locations::Vector{GeoPoint} # These are Edge UPFs (UL-CL) in two-tier mode
    gnb_to_upf_map::Vector{Int} # Index of UPF for each gNB

    # Two-Tier Architecture Extensions
    centralized_upf_locations::Vector{GeoPoint} # PSA UPFs
    edge_upf_parent_map::Vector{Int} # Index of Centralized UPF for each Edge UPF

    # Municipality Distribution
    municipalities::Vector{Municipality}
    municipality_bins::Dict{String,Vector{Int}} # Muni Code -> List of gNB indices
    municipality_probs::Vector{Float64} # Probability of each municipality (aligned with municipalities vector)

    # Graph Representation
    graph::AbstractGraph
end

end
