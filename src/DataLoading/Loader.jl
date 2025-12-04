# Network Deployment Helpers
function load_raw_gnb_data(csv_paths::Vector{String})
    df = DataFrame()
    for path in csv_paths
        if isfile(path)
            @debug "Reading gNB data from $path..."
            temp_df = CSV.read(path, DataFrame; header=[:radio, :mcc, :net, :area, :cell, :unit, :lon, :lat, :range, :samples, :changeable, :created, :updated, :avg_signal])
            append!(df, temp_df)
        else
            @warn "File not found: $path"
        end
    end

    if nrow(df) == 0
        error("No data loaded from provided CSV paths.")
    end
    return df
end

function get_bounding_box(municipalities::Vector{Municipality})
    min_lat, max_lat = 90.0, -90.0
    min_lon, max_lon = 180.0, -180.0

    for m in municipalities
        min_lat = min(min_lat, m.location.lat)
        max_lat = max(max_lat, m.location.lat)
        min_lon = min(min_lon, m.location.lon)
        max_lon = max(max_lon, m.location.lon)
    end

    # Add a small buffer
    return (
        min_lat=min_lat - 0.5,
        max_lat=max_lat + 0.5,
        min_lon=min_lon - 0.5,
        max_lon=max_lon + 0.5
    )
end

function filter_gnbs_by_location!(df::DataFrame, municipalities::Vector{Municipality})
    if isempty(municipalities)
        @warn "No municipalities loaded. Skipping gNB filtering by location."
        return
    end

    bbox = get_bounding_box(municipalities)
    @debug "Filtering gNBs within bounding box: Lat [$(bbox.min_lat), $(bbox.max_lat)], Lon [$(bbox.min_lon), $(bbox.max_lon)]"

    filter!(row -> bbox.min_lat <= row.lat <= bbox.max_lat && bbox.min_lon <= row.lon <= bbox.max_lon, df)
end

function filter_gnbs_by_operator!(df::DataFrame, operator_net_id::Int)
    filter!(row -> row.net == operator_net_id, df)
    @info "Filtered $(nrow(df)) gNBs for Operator ID $operator_net_id."
    if nrow(df) == 0
        @warn "No gNBs found for Operator ID $operator_net_id. Simulation might fail or be empty."
    end
end

function perform_clustering(df::DataFrame, num_upfs::Int)
    if nrow(df) == 0
        @warn "Cannot perform clustering on 0 gNBs. Returning empty UPF locations."
        return Vector{GeoPoint}(), Vector{Int}()
    end

    gnb_coords = Matrix{Float64}(undef, 2, nrow(df))
    gnb_coords[1, :] = df.lon
    gnb_coords[2, :] = df.lat

    actual_k = min(num_upfs, nrow(df))
    @info "Clustering $(nrow(df)) gNBs into $actual_k UPF regions..."

    R = kmeans(gnb_coords, actual_k; maxiter=100)

    upf_locs = Vector{GeoPoint}()
    for i in 1:actual_k
        # Centroids are [lon, lat]
        push!(upf_locs, GeoPoint(R.centers[2, i], R.centers[1, i]))
    end

    gnb_to_upf = R.assignments
    return upf_locs, gnb_to_upf
end

function calculate_municipality_probs(municipalities::Vector{Municipality})
    total_muni_pop = sum([m.population for m in municipalities])
    if total_muni_pop == 0
        return fill(1.0 / length(municipalities), length(municipalities))
    end
    return [Float64(m.population) / total_muni_pop for m in municipalities]
end

function perform_hierarchical_clustering(edge_upf_locs::Vector{GeoPoint}, num_centralized_upfs::Int)
    if isempty(edge_upf_locs)
        return Vector{GeoPoint}(), Vector{Int}()
    end
    
    # Convert GeoPoints to Matrix for K-means
    coords = Matrix{Float64}(undef, 2, length(edge_upf_locs))
    for (i, p) in enumerate(edge_upf_locs)
        coords[1, i] = p.lon
        coords[2, i] = p.lat
    end

    actual_k = min(num_centralized_upfs, length(edge_upf_locs))
    @info "Clustering $(length(edge_upf_locs)) Edge UPFs into $actual_k Centralized UPF regions..."

    R = kmeans(coords, actual_k; maxiter=100)

    centralized_locs = Vector{GeoPoint}()
    for i in 1:actual_k
        push!(centralized_locs, GeoPoint(R.centers[2, i], R.centers[1, i]))
    end

    edge_to_centralized = R.assignments
    return centralized_locs, edge_to_centralized
end

# Main Functions
function load_and_deploy_network(csv_paths::Vector{String}, operator_net_id::Int, num_upfs::Int, data_dir::String, config::SimConfig)
    df = load_raw_gnb_data(csv_paths)
    muni_csv_path = joinpath(data_dir, "municipalities.csv")
    muni_geojson_path = joinpath(data_dir, "regions.geojson")

    municipalities = Vector{Municipality}()
    if isfile(muni_csv_path)
        municipalities = load_municipalities(muni_csv_path, muni_geojson_path)
    else
        @warn "Municipality data not found at $muni_csv_path. Using empty list."
    end
    filter_gnbs_by_location!(df, municipalities)
    filter_gnbs_by_operator!(df, operator_net_id)
    gnb_points = [GeoPoint(r.lat, r.lon) for r in eachrow(df)]
    upf_locs, gnb_to_upf = perform_clustering(df, num_upfs)
    
    # Initialize empty fields for two-tier architecture
    centralized_upf_locs = Vector{GeoPoint}()
    edge_upf_parent_map = Vector{Int}()

    # Handle Two-Tier Scenario
    if config.scenario == :two_tier
        if config.num_centralized_upfs > 0
            centralized_upf_locs, edge_upf_parent_map = perform_hierarchical_clustering(upf_locs, config.num_centralized_upfs)
        else
            @warn "Scenario is :two_tier but num_centralized_upfs is 0. Falling back to single tier."
        end
    end

    # Build Graph (Pass centralized UPFs if they exist)
    mg = build_graph(upf_locs, gnb_points, gnb_to_upf, centralized_upf_locs, edge_upf_parent_map)
    
    muni_probs = calculate_municipality_probs(municipalities)
    municipality_bins = Dict{String,Vector{Int}}()
    
    return NetworkTopology(
        gnb_points, 
        upf_locs, 
        gnb_to_upf, 
        centralized_upf_locs,
        edge_upf_parent_map,
        municipalities, 
        municipality_bins, 
        muni_probs, 
        mg
    )
end

function load_and_cluster(csv_path::String, operator_id::Int, num_upfs::Int;
                          min_lat::Float64=-90.0, max_lat::Float64=90.0,
                          min_lon::Float64=-180.0, max_lon::Float64=180.0)
    @info "Loading gNB data from $csv_path for Operator $operator_id..."
    df = CSV.read(csv_path, DataFrame; header=[:radio, :mcc, :net, :area, :cell, :unit, :lon, :lat, :range, :samples, :changeable, :created, :updated, :avg_signal])

    # Filter valid coordinates based on provided bounds
    filter!(row -> min_lat <= row.lat <= max_lat && min_lon <= row.lon <= max_lon, df)
    filter!(row -> row.net == operator_id, df)
    gnb_coords = Matrix{Float64}(undef, 2, nrow(df))
    gnb_coords[1, :] = df.lon
    gnb_coords[2, :] = df.lat
    @info "Found $(nrow(df)) valid gNBs."
    # K-Means for UPFs
    k = min(num_upfs, nrow(df))
    @info "Clustering into $k UPF regions..."
    R = kmeans(gnb_coords, k; maxiter=100)
    upf_lons = R.centers[1, :]
    upf_lats = R.centers[2, :]

    return df, upf_lons, upf_lats
end
