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

            # Check properties for 'id' (Standard)
            if haskey(feature, :properties) && haskey(feature.properties, :id)
                muni_id = string(feature.properties.id)
            # Fallback: Check top-level id
            elseif haskey(feature, :id)
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
    
    # Expect Standard CSV: id,name,population,lat,lon
    df = CSV.read(csv_path, DataFrame)

    # Load Polygons if available
    polygons = Dict{String,Any}()
    if !isempty(geojson_path) && isfile(geojson_path)
        polygons = load_municipality_polygons(geojson_path)
    end

    municipalities = Vector{Municipality}()

    for row in eachrow(df)
        # Standard Format: id,name,population,lat,lon
        code = string(row.id)
        # Ensure 5 digits for Spain/USA FIPS consistency if needed, but let's trust the data
        # Actually, Spain codes are 5 digits, USA FIPS are 5 digits.
        # If the CSV has them as numbers, they might lose leading zeros.
        if length(code) < 5
            code = lpad(code, 5, '0')
        end
        
        name = ismissing(row.name) ? "Unknown" : string(row.name)
        pop = ismissing(row.population) ? 0 : Int(row.population)
        area = 0.0 # Not in standard CSV yet
        lat = ismissing(row.lat) ? 0.0 : Float64(row.lat)
        lon = ismissing(row.lon) ? 0.0 : Float64(row.lon)

        # Get Polygon
        poly = get(polygons, code, nothing)

        # Filter invalid coordinates
        if lat != 0.0 && lon != 0.0
            push!(municipalities, Municipality(code, name, pop, GeoPoint(lat, lon), area, poly))
        end
    end
    println("  Loaded $(length(municipalities)) municipalities.")
    return municipalities
end

function load_and_deploy_network(csv_paths::Vector{String}, operator_net_id::Int, num_upfs::Int, data_dir::String)
    println("Loading gNB data from $(length(csv_paths)) files for Operator ID: $operator_net_id...")
    
    df = DataFrame()
    for path in csv_paths
        if isfile(path)
            println("  Reading $path...")
            temp_df = CSV.read(path, DataFrame; header=[:radio, :mcc, :net, :area, :cell, :unit, :lon, :lat, :range, :samples, :changeable, :created, :updated, :avg_signal])
            append!(df, temp_df)
        else
            println("  Warning: File not found: $path")
        end
    end

    if nrow(df) == 0
        error("No data loaded from provided CSV paths.")
    end

    # --- Load Municipality Data First (to determine bounding box) ---
    muni_csv_path = joinpath(data_dir, "municipalities.csv")
    muni_geojson_path = joinpath(data_dir, "regions.geojson")

    municipalities = Vector{Municipality}()
    if isfile(muni_csv_path)
        municipalities = load_municipalities(muni_csv_path, muni_geojson_path)
    else
        println("Warning: Municipality data not found at $muni_csv_path. Using empty list.")
    end
    
    # Determine Bounding Box from Municipalities
    min_lat, max_lat = 90.0, -90.0
    min_lon, max_lon = 180.0, -180.0
    
    if !isempty(municipalities)
        for m in municipalities
            min_lat = min(min_lat, m.location.lat)
            max_lat = max(max_lat, m.location.lat)
            min_lon = min(min_lon, m.location.lon)
            max_lon = max(max_lon, m.location.lon)
        end
        # Add a small buffer
        min_lat -= 0.5; max_lat += 0.5
        min_lon -= 0.5; max_lon += 0.5
        
        println("  Filtering gNBs within Bounding Box: Lat [$min_lat, $max_lat], Lon [$min_lon, $max_lon]")
        
        # Filter gNBs
        filter!(row -> min_lat <= row.lat <= max_lat && min_lon <= row.lon <= max_lon, df)
    else
        println("  Warning: No municipalities loaded. Skipping gNB filtering by location.")
    end

    # Filter for Specific Operator
    filter!(row -> row.net == operator_net_id, df)

    gnb_coords = Matrix{Float64}(undef, 2, nrow(df))
    gnb_coords[1, :] = df.lon
    gnb_coords[2, :] = df.lat

    println("  Found $(nrow(df)) valid gNBs for Operator $operator_net_id.")

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
