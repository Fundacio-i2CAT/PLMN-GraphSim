module Types

using Agents
using Graphs
using MetaGraphsNext
using Distributions
using Random
using GeometryBasics

export FAR, SessionContext5G, ForwardingEntry6GRUPA, QoSConfig6GRUPA
export SimGlobalState, GeoPoint, NetworkTopology, GUPFState6GRUPA, Municipality, SimConfig
export SPAIN_POPULATION, USA_POPULATION, RATIO_UNDER_15, PHONE_ADOPTION_OVER_15, EFFECTIVE_POPULATION, EFFECTIVE_POPULATION_USA
export haversine_distance

# --- Constants ---
const SPAIN_POPULATION = 49_442_844 # INE, 2025
const USA_POPULATION = 335_000_000 # Approx 2023

# Demographics: ~14.5% under 15 (no phone), 96% of >15 have phone, source INE 2023
const RATIO_UNDER_15 = 0.145
const PHONE_ADOPTION_OVER_15 = 0.96
const EFFECTIVE_POPULATION = SPAIN_POPULATION * (1 - RATIO_UNDER_15) * PHONE_ADOPTION_OVER_15
const EFFECTIVE_POPULATION_USA = USA_POPULATION * (1 - RATIO_UNDER_15) * PHONE_ADOPTION_OVER_15

# --- Simulation Constants ---
# Estimated memory footprint per 5G Session (PDR + FAR + QER + URR + Context overhead)
# This is a theoretical value for a C/C++ data plane implementation, not the Julia struct size.
const BYTES_PER_SESSION_5G = 512 

# --- Shared Structures ---
struct GeoPoint
    lat::Float64
    lon::Float64
end

"""
    haversine_distance(p1::GeoPoint, p2::GeoPoint)

Calculates the Haversine distance between two GeoPoints in kilometers.
"""
function haversine_distance(p1::GeoPoint, p2::GeoPoint)
    R = 6371.0 # Earth radius in km
    dlat = deg2rad(p2.lat - p1.lat)
    dlon = deg2rad(p2.lon - p1.lon)
    a = sin(dlat/2)^2 + cos(deg2rad(p1.lat)) * cos(deg2rad(p2.lat)) * sin(dlon/2)^2
    c = 2 * atan(sqrt(a), sqrt(1-a))
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

struct SessionContext5G
    ul_teid::UInt32
    dl_teid::UInt32
    ul_far::FAR
    dl_far::FAR
end

struct ForwardingEntry6GRUPA
    dest_prefix::UInt32
    mask::UInt32
    output_interface::Int32
end

struct QoSConfig6GRUPA
    qfi::Int8
    priority::Int8
    packet_delay_budget::Float64
    packet_error_rate::Float64
end

struct SimConfig
    min_sessions::Int
    max_sessions::Int
    scale_factor::Int
    duration::Float64
    mean_session_duration::Float64
    mean_offline_duration::Float64
end

# --- Simulation State ---
mutable struct SimGlobalState
    # Config
    config::SimConfig

    # 5G State: Per UPF (Vector of Vectors)
    # Dynamic: Grows with number of sessions
    upf_sessions_5g::Vector{Vector{SessionContext5G}}

    # 6G-RUPA State: Per GUPF (Vector of Vectors)
    # Static/Topology-based: Depends on number of gNBs/subnets served
    forwarding_tables_6g::Vector{Vector{ForwardingEntry6GRUPA}}
    qos_profiles_6g::Vector{QoSConfig6GRUPA}

    # Metrics History
    history_time::Vector{Float64}
    history_total_5g_mb::Vector{Float64}
    history_max_upf_5g_mb::Vector{Float64} # The bottleneck UPF
    history_mean_upf_5g_mb::Vector{Float64}
    history_median_upf_5g_mb::Vector{Float64}
    
    history_total_6g_mb::Vector{Float64}
    history_max_upf_6g_mb::Vector{Float64}
    history_mean_upf_6g_mb::Vector{Float64}
    history_median_upf_6g_mb::Vector{Float64}
end

struct GUPFState6GRUPA
    forwarding_table::Vector{ForwardingEntry6GRUPA}
    qos_profiles::Vector{QoSConfig6GRUPA}
end

# --- Network Topology ---

struct NetworkTopology
    gnb_locations::Vector{GeoPoint}
    upf_locations::Vector{GeoPoint}
    gnb_to_upf_map::Vector{Int} # Index of UPF for each gNB

    # Municipality Distribution (More granular)
    municipalities::Vector{Municipality}
    municipality_bins::Dict{String,Vector{Int}} # Muni Code -> List of gNB indices
    municipality_probs::Vector{Float64} # Probability of each municipality (aligned with municipalities vector)
    
    # Graph Representation
    # Nodes: 
    #   1..N_gNB (gNBs)
    #   N_gNB+1..N_gNB+N_UPF (UPFs)
    #   Dynamic: Agents
    graph::AbstractGraph 
end

end
