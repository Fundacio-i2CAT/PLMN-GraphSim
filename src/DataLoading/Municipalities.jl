# Municipality Loading
function load_municipality_polygons(geojson_path::String)
    @debug "Loading municipality polygons from $geojson_path"
    json_str = read(geojson_path, String)
    json_obj = JSON3.read(json_str)

    polygons = Dict{String,Any}()

    if haskey(json_obj, :features)
        for feature in json_obj.features
            process_geojson_feature!(polygons, feature)
        end
    end
    @debug "Loaded $(length(polygons)) polygons."
    return polygons
end

function process_geojson_feature!(polygons::Dict{String,Any}, feature)
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

function parse_municipality_row(row, polygons::Dict{String,Any})
    # Standard Format: id,name,population,lat,lon
    code = string(row.id)
    name = ismissing(row.name) ? "Unknown" : string(row.name)
    pop = ismissing(row.population) ? 0 : Int(row.population)
    area = 0.0 # Not in standard CSV yet
    lat = ismissing(row.lat) ? 0.0 : Float64(row.lat)
    lon = ismissing(row.lon) ? 0.0 : Float64(row.lon)
    poly = get(polygons, code, nothing)
    
    if lat != 0.0 && lon != 0.0
        return Municipality(code, name, pop, GeoPoint(lat, lon), area, poly)
    end
    return nothing
end

function load_municipalities(csv_path::String, geojson_path::String="")
    @debug "Loading municipalities from CSV: $csv_path"
    df = CSV.read(csv_path, DataFrame)

    # Load Polygons if available
    polygons = Dict{String,Any}()
    if !isempty(geojson_path) && isfile(geojson_path)
        polygons = load_municipality_polygons(geojson_path)
    else
        @warn "GeoJSON path empty or file not found: $geojson_path"
    end

    municipalities = Vector{Municipality}()
    for row in eachrow(df)
        muni = parse_municipality_row(row, polygons)
        if !isnothing(muni)
            push!(municipalities, muni)
        end
    end
    @info "Loaded $(length(municipalities)) municipalities."
    return municipalities
end
