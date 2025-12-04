# Municipality Loading
function load_municipality_polygons(geojson_path::String)
    @debug "Loading municipality polygons from $geojson_path"
    json_str = read(geojson_path, String)
    json_obj = JSON3.read(json_str)

    polygons = Dict{String,Any}()

    if json_obj isa JSON3.Object && haskey(json_obj, :features)
        features = json_obj.features
        if !isnothing(features)
            for feature in features
                process_geojson_feature!(polygons, feature)
            end
        end
    end
    @debug "Loaded $(length(polygons)) polygons."
    return polygons
end

function process_geojson_feature!(polygons::Dict{String,Any}, feature)
    if isnothing(feature)
        return
    end
    
    muni_id = nothing

    # Check properties for 'id' (Standard)
    properties = get(feature, :properties, nothing)
    if !isnothing(properties) && haskey(properties, :id)
        raw_id = properties.id
        if raw_id isa Number
            muni_id = string(Int(raw_id))
        elseif raw_id isa String && !isnothing(tryparse(Int, raw_id))
            muni_id = string(parse(Int, raw_id))
        else
            muni_id = string(raw_id)
        end
    # Fallback: Check top-level id
    elseif haskey(feature, :id)
        raw_id = feature.id
        if raw_id isa Number
            muni_id = string(Int(raw_id))
        elseif raw_id isa String && !isnothing(tryparse(Int, raw_id))
            muni_id = string(parse(Int, raw_id))
        else
            muni_id = string(raw_id)
        end
    end

    if !isnothing(muni_id) && haskey(feature, :geometry)
        # Convert JSON3 geometry object to GeoJSON wrapper/GeometryBasics
        geometry = feature.geometry
        if !isnothing(geometry)
            geom_str = JSON3.write(geometry)
            geom_obj = GeoJSON.read(geom_str)
            polygons[muni_id] = geom_obj
        end
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
