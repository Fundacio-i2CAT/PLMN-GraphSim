module DataLoading

using CSV
using DataFrames
using Clustering
using HTTP
using JSON
using JSON3
using GeoJSON
using Graphs
using MetaGraphsNext
using ..Types

export load_and_deploy_network, load_and_cluster, load_municipalities

# INE API Base URL
const INE_BASE_URL = "https://servicios.ine.es/wstempus/js/es"

function load_municipality_polygons(geojson_path::String)
    println("Loading Municipality Polygons from $geojson_path...")
    json_str = read(geojson_path, String)
    # Use JSON3 directly to ensure we get the 'id'
    json_obj = JSON3.read(json_str)

    polygons = Dict{String,Any}()

    if haskey(json_obj, :features)
        for feature in json_obj.features
            muni_id = nothing

            # Check properties for CODIGOINE (ESRI format)
            if haskey(feature, :properties) && haskey(feature.properties, :CODIGOINE)
                muni_id = string(feature.properties.CODIGOINE)
            end

            # Fallback: Check top-level id or other properties
            if isnothing(muni_id) && haskey(feature, :id)
                muni_id = string(feature.id)
            end

            if !isnothing(muni_id) && haskey(feature, :geometry)
                # Convert JSON3 geometry object to GeoJSON wrapper/GeometryBasics
                geom_str = JSON3.write(feature.geometry)
                geom_obj = GeoJSON.read(geom_str)
                polygons[muni_id] = geom_obj
            end
        end
    end

    println("  Loaded $(length(polygons)) polygons.")
    return polygons
end

function load_municipalities(csv_path::String, geojson_path::String="")
    println("Loading Municipalities from $csv_path...")
    df = CSV.read(csv_path, DataFrame; delim=';', decimal=',')

    # Load Polygons if available
    polygons = Dict{String,Any}()
    if !isempty(geojson_path) && isfile(geojson_path)
        polygons = load_municipality_polygons(geojson_path)
    end

    municipalities = Vector{Municipality}()

    for row in eachrow(df)
        # Parse Code (COD_INE)
        # CSV format: 01001000000 (11 digits)
        # GeoJSON format: 01001 (5 digits)
        # We need to extract the first 5 digits from the CSV code to match.
        full_code = string(row.COD_INE)

        # Ensure we have at least 5 digits
        if length(full_code) >= 5
            # Take first 5 digits: Province (2) + Municipality (3)
            code = full_code[1:5]
        else
            code = full_code
        end

        # Parse Name
        name = row.NOMBRE_ACTUAL

        # Parse Population
        pop = ismissing(row.POBLACION_MUNI) ? 0 : Int(row.POBLACION_MUNI)

        # Parse Area (Superficie)
        area = ismissing(row.SUPERFICIE) ? 0.0 : Float64(row.SUPERFICIE)

        # Parse Coordinates
        lat = row.LATITUD_ETRS89
        lon = row.LONGITUD_ETRS89

        # Get Polygon
        poly = get(polygons, code, nothing)

        # Filter invalid coordinates
        if !ismissing(lat) && !ismissing(lon) && lat != 0.0 && lon != 0.0
            if lat > 35.0
                push!(municipalities, Municipality(code, name, pop, GeoPoint(lat, lon), area, poly))
            end
        end
    end
    println("  Loaded $(length(municipalities)) municipalities.")
    return municipalities
end

function load_and_deploy_network(csv_path::String, operator_net_id::Int, num_upfs::Int)
    println("Loading gNB data from $csv_path for Operator ID: $operator_net_id...")
    df = CSV.read(csv_path, DataFrame; header=[:radio, :mcc, :net, :area, :cell, :unit, :lon, :lat, :range, :samples, :changeable, :created, :updated, :avg_signal])

    # Filter valid coordinates for Spain (approx bounding box)
    filter!(row -> 35.0 <= row.lat <= 45.0 && -19.0 <= row.lon <= 5.0, df)

    # Filter for Specific Operator
    filter!(row -> row.net == operator_net_id, df)

    gnb_coords = Matrix{Float64}(undef, 2, nrow(df))
    gnb_coords[1, :] = df.lon
    gnb_coords[2, :] = df.lat

    println("  Found $(nrow(df)) valid gNBs for Operator $operator_net_id.")

    # --- Load Municipality Data ---
    data_dir = dirname(csv_path)
    muni_csv_path = joinpath(data_dir, "municipalities_coordinates.csv")
    muni_geojson_path = joinpath(data_dir, "esri_municipios.geojson")

    municipalities = Vector{Municipality}()
    if isfile(muni_csv_path)
        municipalities = load_municipalities(muni_csv_path, muni_geojson_path)
    else
        println("Warning: Municipality data not found at $muni_csv_path. Using empty list.")
    end
    municipality_bins = Dict{String,Vector{Int}}()
    gnb_points = [GeoPoint(r.lat, r.lon) for r in eachrow(df)]
    final_municipalities = municipalities

    # Calculate probabilities based on population
    total_muni_pop = sum([m.population for m in final_municipalities])
    muni_probs = [Float64(m.population) / total_muni_pop for m in final_municipalities]

    println("  Municipalities available for agents: $(length(final_municipalities))")

    # --- Deploy UPFs using K-Means Clustering ---
    actual_k = min(num_upfs, nrow(df))
    println("Deploying $actual_k UPFs using K-Means clustering...")

    R = kmeans(gnb_coords, actual_k; maxiter=100)

    upf_locs = Vector{GeoPoint}()
    for i in 1:actual_k
        # Centroids are [lon, lat]
        push!(upf_locs, GeoPoint(R.centers[2, i], R.centers[1, i]))
    end

    # Map each gNB to nearest UPF (assignments from kmeans)
    gnb_to_upf = R.assignments

    # --- Build Graph ---
    # We use MetaGraph with Tuple labels: (:gNB, id), (:UPF, id), (:Agent, id)
    # Vertex Data: GeoPoint
    # Edge Data: Distance/Latency (Float64) in Kilometers
    # Topology Rules:
    # 1. Agents -> Nearest gNB (Dynamic, added in Simulation)
    # 2. gNBs -> Closest UPF (Static, K-Means Centroid)
    # 3. UPFs are disjoint (No edges between UPFs)
    
    mg = MetaGraph(
        Graph(), # Underlying graph
        label_type = Tuple{Symbol, Int}, # Vertex Label Type
        vertex_data_type = GeoPoint, # Vertex Data Type
        edge_data_type = Float64 # Edge Data Type (Distance in km)
    )

    # Add UPFs
    for (i, loc) in enumerate(upf_locs)
        add_vertex!(mg, (:UPF, i), loc)
    end

    # Add gNBs and connect to UPFs
    for (i, loc) in enumerate(gnb_points)
        add_vertex!(mg, (:gNB, i), loc)
        
        # Connect to assigned UPF
        upf_idx = gnb_to_upf[i]
        
        # Calculate distance
        upf_loc = upf_locs[upf_idx]
        dist_km = haversine_distance(loc, upf_loc)
        
        add_edge!(mg, (:gNB, i), (:UPF, upf_idx), dist_km)
    end

    return NetworkTopology(gnb_points, upf_locs, gnb_to_upf, final_municipalities, municipality_bins, muni_probs, mg)
end

# --- Load Data & Cluster (for Plotting) ---
function load_and_cluster(csv_path::String, operator_id::Int, num_upfs::Int)
    println("Loading gNB data from $csv_path for Operator $operator_id...")
    df = CSV.read(csv_path, DataFrame; header=[:radio, :mcc, :net, :area, :cell, :unit, :lon, :lat, :range, :samples, :changeable, :created, :updated, :avg_signal])

    # Filter valid coordinates for Spain (Mainland + Ceuta/Melilla, excluding Canary Islands)
    filter!(row -> 35.0 <= row.lat <= 45.0 && -19.0 <= row.lon <= 5.0, df)

    # Filter for Specific Operator
    filter!(row -> row.net == operator_id, df)

    gnb_coords = Matrix{Float64}(undef, 2, nrow(df))
    gnb_coords[1, :] = df.lon
    gnb_coords[2, :] = df.lat

    println("  Found $(nrow(df)) valid gNBs.")

    # K-Means for UPFs
    k = min(num_upfs, nrow(df))
    println("Clustering into $k UPF regions...")
    R = kmeans(gnb_coords, k; maxiter=100)

    upf_lons = R.centers[1, :]
    upf_lats = R.centers[2, :]

    return df, upf_lons, upf_lats
end

end
