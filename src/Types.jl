module Types

using Agents
using Graphs
using MetaGraphsNext
using Distributions
using Random
using GeometryBasics

export FAR, SessionContext5G, ForwardingEntry6GRUPA, ForwardingState5G, SessionSimMetadata
export SimGlobalState, GeoPoint, NetworkTopology, GUPFState6GRUPA, Municipality, SimConfig
export haversine_distance

# --- Constants ---

# --- Simulation Constants ---
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

struct ForwardingState5G
    ul_teid::UInt32
    dl_teid::UInt32
    ul_far::FAR
    dl_far::FAR
end

struct SessionSimMetadata
    serving_upf_index::Int # The UPF currently serving the gNB (UL-CL)
    anchor_upf_index::Int  # The UPF acting as PDU Session Anchor (PSA)
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

struct SimConfig
    min_sessions::Int
    max_sessions::Int
    scale_factor::Int
    duration::Float64
    mean_session_duration::Float64
    mean_offline_duration::Float64
    # Architecture Configuration
    scenario::Symbol # :basic, :two_tier, :roaming
    num_centralized_upfs::Int # For :two_tier scenario
end

# --- Simulation State ---
mutable struct SimGlobalState
    # Config
    config::SimConfig

    # 5G State: Per UPF (Vector of Vectors)
    # Dynamic: Grows with number of sessions
    # Note: In two-tier mode, this stores sessions for the UL-CL (Edge UPF)
    upf_sessions_5g::Vector{Vector{SessionContext5G}}

    # 6G-RUPA State: Per GUPF (Vector of Vectors)
    # Static/Topology-based: Depends on number of gNBs/subnets served
    forwarding_tables_6grupa::Vector{Vector{ForwardingEntry6GRUPA}}
    centralized_forwarding_tables_6grupa::Vector{Vector{ForwardingEntry6GRUPA}} # For PSA UPFs

    # Metrics History
    history_time::Vector{Float64}
    history_total_5g_mb::Vector{Float64}
    history_max_upf_5g_mb::Vector{Float64} # The bottleneck UPF
    history_mean_upf_5g_mb::Vector{Float64}
    history_median_upf_5g_mb::Vector{Float64}
    
    history_total_6grupa_mb::Vector{Float64}
    history_max_gupf_6grupa_mb::Vector{Float64}
    history_mean_gupf_6grupa_mb::Vector{Float64}
    history_median_gupf_6grupa_mb::Vector{Float64}

    history_mean_entries_6grupa::Vector{Float64}
    history_median_entries_6grupa::Vector{Float64}

    # Detailed History (Per UPF over time)
    history_per_upf_5g_mb::Vector{Vector{Float64}}
    history_per_upf_entries_5g::Vector{Vector{Int}}
    history_per_gupf_6grupa_mb::Vector{Vector{Float64}}
    history_per_gupf_entries_6grupa::Vector{Vector{Int}}
end

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

    # Municipality Distribution (More granular)
    municipalities::Vector{Municipality}
    municipality_bins::Dict{String,Vector{Int}} # Muni Code -> List of gNB indices
    municipality_probs::Vector{Float64} # Probability of each municipality (aligned with municipalities vector)
    
    # Graph Representation
    # Nodes: 
    #   1..N_gNB (gNBs)
    #   N_gNB+1..N_gNB+N_UPF (Edge UPFs)
    #   ... (Centralized UPFs if present)
    #   Dynamic: Agents
    graph::AbstractGraph 
end

end
