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
    scenario::Symbol # :basic, :two_tier, :roaming
    num_centralized_upfs::Int # For :two_tier scenario
    sampling_interval::Float64
end

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

    # Municipality Distribution
    municipalities::Vector{Municipality}
    municipality_bins::Dict{String,Vector{Int}} # Muni Code -> List of gNB indices
    municipality_probs::Vector{Float64} # Probability of each municipality (aligned with municipalities vector)

    # Graph Representation
    graph::AbstractGraph
end

end
