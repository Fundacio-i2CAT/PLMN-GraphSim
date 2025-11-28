module Types

using Agents
using Graphs
using MetaGraphsNext
using Distributions
using Random

export FAR, SessionContext5G, ForwardingEntry6GRUPA, QoSConfig6GRUPA
export SimGlobalState, GeoPoint, NetworkTopology, GUPFState6GRUPA
export PROVINCE_CENTROIDS

# --- Shared Structures ---
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

struct GeoPoint
    lat::Float64
    lon::Float64
end

struct NetworkTopology
    gnb_locations::Vector{GeoPoint}
    upf_locations::Vector{GeoPoint}
    gnb_to_upf_map::Vector{Int} # Index of UPF for each gNB
    
    # Population Distribution
    province_bins::Dict{String, Vector{Int}}
    province_names::Vector{String}
    province_probs::Vector{Float64}
end

# --- Province Centroids (Approximate) ---
const PROVINCE_CENTROIDS = Dict(
    "Albacete" => GeoPoint(38.9943, -1.8585),
    "Alicante/Alacant" => GeoPoint(38.3452, -0.4810),
    "Almería" => GeoPoint(36.8340, -2.4637),
    "Araba/Álava" => GeoPoint(42.8467, -2.6716),
    "Asturias" => GeoPoint(43.3614, -5.8593),
    "Ávila" => GeoPoint(40.6565, -4.7002),
    "Badajoz" => GeoPoint(38.8794, -6.9706),
    "Balears, Illes" => GeoPoint(39.6953, 3.0176),
    "Barcelona" => GeoPoint(41.3851, 2.1734),
    "Bizkaia" => GeoPoint(43.2630, -2.9350),
    "Burgos" => GeoPoint(42.3439, -3.6969),
    "Cáceres" => GeoPoint(39.4753, -6.3723),
    "Cádiz" => GeoPoint(36.5271, -6.2886),
    "Cantabria" => GeoPoint(43.1828, -3.9878),
    "Castellón/Castelló" => GeoPoint(39.9864, -0.0513),
    "Ciudad Real" => GeoPoint(38.9848, -3.9274),
    "Córdoba" => GeoPoint(37.8882, -4.7794),
    "Coruña, A" => GeoPoint(43.3623, -8.4115),
    "Cuenca" => GeoPoint(40.0704, -2.1374),
    "Gipuzkoa" => GeoPoint(43.3183, -1.9812),
    "Girona" => GeoPoint(41.9794, 2.8214),
    "Granada" => GeoPoint(37.1773, -3.5986),
    "Guadalajara" => GeoPoint(40.6328, -3.1632),
    "Huelva" => GeoPoint(37.2614, -6.9447),
    "Huesca" => GeoPoint(42.1361, -0.4087),
    "Jaén" => GeoPoint(37.7796, -3.7849),
    "León" => GeoPoint(42.5987, -5.5671),
    "Lleida" => GeoPoint(41.6176, 0.6200),
    "Lugo" => GeoPoint(43.0097, -7.5568),
    "Madrid" => GeoPoint(40.4168, -3.7038),
    "Málaga" => GeoPoint(36.7213, -4.4214),
    "Murcia" => GeoPoint(37.9922, -1.1307),
    "Navarra" => GeoPoint(42.8125, -1.6458),
    "Ourense" => GeoPoint(42.3358, -7.8639),
    "Palencia" => GeoPoint(42.0095, -4.5286),
    "Pontevedra" => GeoPoint(42.4299, -8.6446),
    "Rioja, La" => GeoPoint(42.2871, -2.5396),
    "Salamanca" => GeoPoint(40.9701, -5.6635),
    "Segovia" => GeoPoint(40.9429, -4.1088),
    "Sevilla" => GeoPoint(37.3891, -5.9845),
    "Soria" => GeoPoint(41.7666, -2.4735),
    "Tarragona" => GeoPoint(41.1189, 1.2445),
    "Teruel" => GeoPoint(40.3456, -1.1065),
    "Toledo" => GeoPoint(39.8628, -4.0273),
    "Valencia/València" => GeoPoint(39.4699, -0.3763),
    "Valladolid" => GeoPoint(41.6523, -4.7245),
    "Zamora" => GeoPoint(41.5063, -5.7446),
    "Zaragoza" => GeoPoint(41.6488, -0.8891),
    "Ceuta" => GeoPoint(35.8894, -5.3213),
    "Melilla" => GeoPoint(35.2923, -2.9381)
)

end
