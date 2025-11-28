module Types

using Agents
using Graphs
using MetaGraphsNext
using Distributions
using Random
using GeometryBasics

export FAR, SessionContext5G, ForwardingEntry6GRUPA, QoSConfig6GRUPA
export SimGlobalState, GeoPoint, NetworkTopology, GUPFState6GRUPA, Municipality
export REFERENCE_CITIES

# --- Shared Structures ---
struct GeoPoint
    lat::Float64
    lon::Float64
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

# --- Simulation State ---
mutable struct SimGlobalState
    # 5G State: Per UPF (Vector of Vectors)
    upf_sessions_5g::Vector{Vector{SessionContext5G}}
    
    # 6G-RUPA State: Per GUPF (Constant/Topology based)
    forwarding_table_6g::Vector{ForwardingEntry6GRUPA}
    qos_profiles_6g::Vector{QoSConfig6GRUPA}
    
    # Metrics History
    history_time::Vector{Float64}
    history_total_5g_mb::Vector{Float64}
    history_max_upf_5g_mb::Vector{Float64} # The bottleneck UPF
    history_6g_mb::Vector{Float64}
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
    municipality_bins::Dict{String, Vector{Int}} # Muni Code -> List of gNB indices
    municipality_probs::Vector{Float64} # Probability of each municipality (aligned with municipalities vector)
end

# --- Reference Cities (Provincial Capitals & Major Cities) ---
const REFERENCE_CITIES = [
    ("Madrid", GeoPoint(40.4168, -3.7038)),
    ("Barcelona", GeoPoint(41.3851, 2.1734)),
    ("Valencia", GeoPoint(39.4699, -0.3763)),
    ("Seville", GeoPoint(37.3891, -5.9845)),
    ("Zaragoza", GeoPoint(41.6488, -0.8891)),
    ("Málaga", GeoPoint(36.7212, -4.4217)),
    ("Murcia", GeoPoint(37.9922, -1.1307)),
    ("Palma", GeoPoint(39.5696, 2.6502)),
    ("Bilbao", GeoPoint(43.2630, -2.9350)),
    ("Alicante", GeoPoint(38.3452, -0.4810)),
    ("Córdoba", GeoPoint(37.8882, -4.7794)),
    ("Valladolid", GeoPoint(41.6523, -4.7245)),
    ("Vigo", GeoPoint(42.2406, -8.7207)),
    ("Gijón", GeoPoint(43.5322, -5.6611)),
    ("A Coruña", GeoPoint(43.3623, -8.4115)),
    ("Vitoria", GeoPoint(42.8467, -2.6716)),
    ("Granada", GeoPoint(37.1773, -3.5986)),
    ("Oviedo", GeoPoint(43.3619, -5.8494)),
    ("Pamplona", GeoPoint(42.8125, -1.6458)),
    ("Almería", GeoPoint(36.8340, -2.4637)),
    ("San Sebastián", GeoPoint(43.3183, -1.9812)),
    ("Burgos", GeoPoint(42.3439, -3.6969)),
    ("Santander", GeoPoint(43.4623, -3.8099)),
    ("Castellón", GeoPoint(39.9864, -0.0513)),
    ("Albacete", GeoPoint(38.9943, -1.8585)),
    ("Logroño", GeoPoint(42.4623, -2.4449)),
    ("Badajoz", GeoPoint(38.8794, -6.9706)),
    ("Salamanca", GeoPoint(40.9701, -5.6635)),
    ("Huelva", GeoPoint(37.2614, -6.9447)),
    ("Lleida", GeoPoint(41.6176, 0.6200)),
    ("Tarragona", GeoPoint(41.1189, 1.2445)),
    ("León", GeoPoint(42.5987, -5.5671)),
    ("Cádiz", GeoPoint(36.5271, -6.2886)),
    ("Jaén", GeoPoint(37.7749, -3.7902)),
    ("Ourense", GeoPoint(42.3358, -7.8639)),
    ("Lugo", GeoPoint(43.0125, -7.5558)),
    ("Girona", GeoPoint(41.9794, 2.8214)),
    ("Cáceres", GeoPoint(39.4753, -6.3723)),
    ("Santiago", GeoPoint(42.8782, -8.5448)),
    ("Toledo", GeoPoint(39.8628, -4.0273)),
    ("Guadalajara", GeoPoint(40.6328, -3.1602)),
    ("Cuenca", GeoPoint(40.0704, -2.1374)),
    ("Ciudad Real", GeoPoint(38.9848, -3.9274)),
    ("Zamora", GeoPoint(41.5063, -5.7446)),
    ("Palencia", GeoPoint(42.0095, -4.5286)),
    ("Segovia", GeoPoint(40.9429, -4.1088)),
    ("Soria", GeoPoint(41.7640, -2.4688)),
    ("Teruel", GeoPoint(40.3456, -1.1065)),
    ("Huesca", GeoPoint(42.1361, -0.4087)),
    ("Ávila", GeoPoint(40.6565, -4.6813)),
    ("Ceuta", GeoPoint(35.8894, -5.3213)),
    ("Melilla", GeoPoint(35.2923, -2.9381))
]

end
