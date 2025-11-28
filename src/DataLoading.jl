module DataLoading

using CSV
using DataFrames
using Clustering
using HTTP
using JSON
using ..Types

export load_and_deploy_network, load_and_cluster, load_municipalities

# INE API Base URL
const INE_BASE_URL = "https://servicios.ine.es/wstempus/js/es"

function load_municipalities(csv_path::String)
    println("Loading Municipalities from $csv_path...")
    # CSV uses ';' as delimiter and ',' as decimal separator
    df = CSV.read(csv_path, DataFrame; delim=';', decimal=',')
    
    municipalities = Vector{Municipality}()
    
    for row in eachrow(df)
        # Parse Code (COD_INE)
        # Sometimes it's an integer, sometimes string. Ensure string.
        code = string(row.COD_INE)
        
        # Parse Name
        name = row.NOMBRE_ACTUAL
        
        # Parse Population
        pop = ismissing(row.POBLACION_MUNI) ? 0 : Int(row.POBLACION_MUNI)
        
        # Parse Area (Superficie)
        area = ismissing(row.SUPERFICIE) ? 0.0 : Float64(row.SUPERFICIE)
        
        # Parse Coordinates
        # Note: CSV.read with decimal=',' should handle this, but let's be safe
        lat = row.LATITUD_ETRS89
        lon = row.LONGITUD_ETRS89
        
        # Filter invalid coordinates (e.g. 0,0 or missing)
        if !ismissing(lat) && !ismissing(lon) && lat != 0.0 && lon != 0.0
             # Filter Canary Islands (Lat < 30) if desired, but let's keep them if they are in the file
             # The simulation usually filters gNBs, so if we filter munis too it's consistent.
             # Mainland Spain is roughly > 35 Lat.
             if lat > 35.0
                push!(municipalities, Municipality(code, name, pop, GeoPoint(lat, lon), area))
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
    # Mainland Spain + Ceuta/Melilla (Excluding Canary Islands)
    # Lat: 35 to 45, Lon: -19 to 5
    filter!(row -> 35.0 <= row.lat <= 45.0 && -19.0 <= row.lon <= 5.0, df)

    # Filter for Specific Operator
    filter!(row -> row.net == operator_net_id, df)
    
    gnb_coords = Matrix{Float64}(undef, 2, nrow(df))
    gnb_coords[1, :] = df.lon
    gnb_coords[2, :] = df.lat
    
    println("  Found $(nrow(df)) valid gNBs for Operator $operator_net_id.")
    
    # --- Load Municipality Data ---
    # Assume the file is in data/municipalities_coordinates.csv
    # We construct the path relative to the csv_path (which is in data/)
    data_dir = dirname(csv_path)
    muni_csv_path = joinpath(data_dir, "municipalities_coordinates.csv")
    
    municipalities = Vector{Municipality}()
    if isfile(muni_csv_path)
        municipalities = load_municipalities(muni_csv_path)
    else
        println("Warning: Municipality data not found at $muni_csv_path. Using empty list.")
    end

    # --- Bin gNBs to Municipalities ---
    println("Classifying gNBs into municipalities...")
    municipality_bins = Dict{String, Vector{Int}}()
    for m in municipalities
        municipality_bins[m.code] = Int[]
    end
    
    gnb_points = [GeoPoint(r.lat, r.lon) for r in eachrow(df)]
    
    # If we have municipalities, use them for binning
    if !isempty(municipalities)
        for (i, gnb) in enumerate(gnb_points)
            min_dist = Inf
            best_muni_code = ""
            
            # Optimization: Only check munis within a reasonable range? 
            # For 8000 munis and 2000 gNBs, 16M checks is fine (seconds).
            for m in municipalities
                # Simple Euclidean distance squared (sufficient for nearest neighbor on small scale)
                d = (gnb.lat - m.location.lat)^2 + (gnb.lon - m.location.lon)^2
                if d < min_dist
                    min_dist = d
                    best_muni_code = m.code
                end
            end
            
            if haskey(municipality_bins, best_muni_code)
                push!(municipality_bins[best_muni_code], i)
            end
        end
    end

    # Filter municipalities that have coverage (at least 1 gNB)
    # We only want to spawn agents in municipalities where they can connect.
    # OR we spawn them in any municipality and they connect to nearest gNB (even if far).
    # Let's stick to "Only spawn where there is coverage" to avoid artifacts of users connecting 50km away.
    valid_muni_indices = [i for i in 1:length(municipalities) if !isempty(municipality_bins[municipalities[i].code])]
    final_municipalities = municipalities[valid_muni_indices]
    
    # Calculate probabilities based on population
    total_muni_pop = sum([m.population for m in final_municipalities])
    muni_probs = [Float64(m.population) / total_muni_pop for m in final_municipalities]
    
    println("  Municipalities with coverage: $(length(final_municipalities)) / $(length(municipalities))")

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
    
    return NetworkTopology(gnb_points, upf_locs, gnb_to_upf, final_municipalities, municipality_bins, muni_probs)
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
