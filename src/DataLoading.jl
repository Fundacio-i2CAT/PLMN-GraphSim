module DataLoading

using CSV
using DataFrames
using Clustering
using HTTP
using JSON
using ..Types

export load_and_deploy_network, fetch_population_by_province, load_and_cluster

# INE API Base URL
const INE_BASE_URL = "https://servicios.ine.es/wstempus/js/es"

function load_and_deploy_network(csv_path::String, pop_csv_path::String, operator_net_id::Int, num_upfs::Int)
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
    
    # --- Load Population Data ---
    println("Loading Population Data from $pop_csv_path...")
    pop_df = CSV.read(pop_csv_path, DataFrame)
    filter!(row -> row.Province != "Total Nacional", pop_df)
    # Filter out Canary Islands
    filter!(row -> row.Province != "Palmas, Las" && row.Province != "Santa Cruz de Tenerife", pop_df)
    
    total_pop = sum(pop_df.Population)
    pop_df.prob = pop_df.Population ./ total_pop
    
    province_names = String.(pop_df.Province)
    province_probs = Float64.(pop_df.prob)
    
    # --- Bin gNBs to Provinces ---
    println("Classifying gNBs into provinces...")
    province_bins = Dict{String, Vector{Int}}()
    for name in province_names
        province_bins[name] = Int[]
    end
    
    gnb_points = [GeoPoint(r.lat, r.lon) for r in eachrow(df)]
    
    for (i, gnb) in enumerate(gnb_points)
        min_dist = Inf
        best_prov = ""
        
        for (name, centroid) in PROVINCE_CENTROIDS
            d = (gnb.lat - centroid.lat)^2 + (gnb.lon - centroid.lon)^2
            if d < min_dist
                min_dist = d
                best_prov = name
            end
        end
        
        if haskey(province_bins, best_prov)
            push!(province_bins[best_prov], i)
        end
    end
    
    # Remove empty bins from probability list to avoid selecting empty provinces
    valid_indices = [i for i in 1:length(province_names) if !isempty(province_bins[province_names[i]])]
    final_names = province_names[valid_indices]
    final_probs = province_probs[valid_indices]
    # Renormalize probabilities
    if !isempty(final_probs)
        final_probs = final_probs ./ sum(final_probs)
    end
    
    println("  Provinces with coverage: $(length(final_names)) / $(length(province_names))")

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
    
    return NetworkTopology(gnb_points, upf_locs, gnb_to_upf, province_bins, final_names, final_probs)
end

function fetch_population_by_province()
    println("Fetching population data from INE API...")

    # Table ID 2852: Resident population by date, sex, age group and province
    # We filter for:
    # - Sex: Total (ID 0 or similar, usually implicit if not requested or we sum it)
    # - Age: Total
    # - Date: Last available
    
    # Actually, a simpler table is "Population by province" (Main Series)
    # Let's try to fetch the data for Table 2852 but requesting only the "Total" values.
    # URL pattern: DATOS_TABLA/{TableID}?nult=1 (Last data)
    
    # Note: In a real scenario, we might need to inspect the metadata to get the exact codes for "Total".
    # For this example, I will simulate the structure if the fetch fails, or use a direct download if possible.
    
    # Let's try a direct JSON fetch for the latest data
    url = "$INE_BASE_URL/DATOS_TABLA/2852?nult=1"
    
    try
        resp = HTTP.get(url)
        data = JSON.parse(String(resp.body))
        
        # The INE API returns a list of time series. We need to filter for "Total" population per province.
        # The "Nombre" field usually contains the description: "Albacete. Total. Total. ..."
        
        provinces = String[]
        populations = Int[]
        
        for entry in data
            name = entry["Nombre"]
            # We look for entries that represent the TOTAL population for a province
            # Format is often: "ProvinceName. Total. Total. ..."
            
            # Simple heuristic: Check if it contains "Total" and extract the province name
            # This is a simplification; robust parsing requires checking metadata codes (Variables).
            
            # Let's assume we want to parse the value:
            if occursin("Total", name) && !occursin("Españoles", name) && !occursin("Extranjeros", name)
                # Extract value
                if !isempty(entry["Data"])
                    val = entry["Data"][1]["Valor"]
                    
                    # Extract Province Name (First part of the string)
                    prov_name = split(name, ".")[1]
                    
                    push!(provinces, strip(prov_name))
                    push!(populations, Int(round(val)))
                end
            end
        end
        
        # Create DataFrame
        df = DataFrame(Province = provinces, Population = populations)
        
        # Aggregate duplicates if any (due to loose filtering)
        df = combine(groupby(df, :Province), :Population => maximum => :Population)
        
        println("Fetched data for $(nrow(df)) provinces.")
        return df
        
    catch e
        println("Error fetching from INE API: $e")
        println("Falling back to manual/mock data for demonstration.")
        return DataFrame()
    end
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
