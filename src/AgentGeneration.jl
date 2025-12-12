module AgentGeneration

using ..Types
using Random
using GeometryBasics
using PolygonOps
using Logging
using GeoJSON

export select_agent_location, generate_agent_locations

"""
    select_agent_location(topology::NetworkTopology)

Selects a random location for an agent based on the population distribution.
Uses Municipality-based distribution with Polygon containment (if available) or circular approximation.
Returns a GeoPoint.
"""
function select_agent_location(topology::NetworkTopology)
    # Check if we have granular municipality data
    if !isempty(topology.municipalities) && !isempty(topology.municipality_probs)
        return select_agent_location_municipality(topology)
    else
        # Fallback (should not happen)
        gnb_idx = rand(1:length(topology.gnb_locations))
        gnb = topology.gnb_locations[gnb_idx]
        @warn "Using fallback agent location selection (random gNB)."
        return GeoPoint(gnb.lat, gnb.lon)
    end
end

function select_agent_location_municipality(topology::NetworkTopology)
    # 1. Select Municipality based on Population Probability
    r = rand()
    cumulative = 0.0
    selected_muni_idx = 0
    
    for (i, prob) in enumerate(topology.municipality_probs)
        cumulative += prob
        if r <= cumulative
            selected_muni_idx = i
            break
        end
    end
    
    # Fallback
    if selected_muni_idx == 0 && !isempty(topology.municipalities)
        selected_muni_idx = length(topology.municipalities)
    end
    
    muni = topology.municipalities[selected_muni_idx]
    # @debug "Selected municipality for agent: $(muni.name)"
    
    # 2. Generate Point
    if !isnothing(muni.polygon)
        return select_point_in_polygon(muni)
    else
        return select_point_in_circle(muni)
    end
end

function select_point_in_circle(muni::Municipality)
    # Area is in hectares. 1 hectare = 10,000 m^2.
    area_m2 = muni.area * 10000.0
    # Ensure min radius of 500m for very small/zero area data points
    radius_meters = max(sqrt(area_m2 / pi), 500.0)
    
    # Random point in circle (Uniform distribution)
    dist_r = radius_meters * sqrt(rand())
    theta = 2 * pi * rand()
    
    dy = dist_r * sin(theta)
    dx = dist_r * cos(theta)
    
    lat_offset = dy / 111132.0
    lon_offset = dx / (111132.0 * cos(deg2rad(muni.location.lat)))
    
    new_lat = muni.location.lat + lat_offset
    new_lon = muni.location.lon + lon_offset
    
    return GeoPoint(new_lat, new_lon)
end

function get_bbox(poly)
    min_lon, max_lon = 180.0, -180.0
    min_lat, max_lat = 90.0, -90.0
    
    function update_bounds!(pts)
        for pt in pts
            lon = pt[1]
            lat = pt[2]
            min_lon = min(min_lon, lon)
            max_lon = max(max_lon, lon)
            min_lat = min(min_lat, lat)
            max_lat = max(max_lat, lat)
        end
    end

    if isa(poly, GeometryBasics.Polygon)
        update_bounds!(coordinates(poly))
    elseif isa(poly, GeometryBasics.MultiPolygon)
        for p in poly.polygons
            update_bounds!(coordinates(p))
        end
    elseif isa(poly, GeoJSON.Polygon)
        coords = GeoJSON.coordinates(poly)
        update_bounds!(coords[1])
    elseif isa(poly, GeoJSON.MultiPolygon)
        for p_coords in GeoJSON.coordinates(poly)
            update_bounds!(p_coords[1])
        end
    end
    
    return min_lon, max_lon, min_lat, max_lat
end

function select_point_in_polygon(muni::Municipality)
    # Rejection Sampling
    # Use bounding box of the polygon
    min_lon, max_lon, min_lat, max_lat = get_bbox(muni.polygon)
    
    # Try up to 100 times to find a point inside
    for _ in 1:100
        lat = min_lat + rand() * (max_lat - min_lat)
        lon = min_lon + rand() * (max_lon - min_lon)
        
        # Point for PolygonOps (usually [x, y] -> [lon, lat])
        pt = Point2(lon, lat) 
        
        if is_point_inside(pt, muni.polygon)
            return GeoPoint(lat, lon)
        end
    end
    
    # Fallback if we can't find a point (e.g. very weird shape or bad centroid)
    return select_point_in_circle(muni)
end

function is_point_inside(pt, poly)
    if isa(poly, GeometryBasics.Polygon)
        # Check exterior
        # coordinates(poly) returns the exterior ring points (or LineString)
        return is_point_inside_coords(pt, coordinates(poly))
        
    elseif isa(poly, GeometryBasics.MultiPolygon)
        # Iterate over the polygons in the multipolygon
        for p in poly.polygons
            if is_point_inside(pt, p)
                return true
            end
        end
        return false
    elseif isa(poly, GeoJSON.Polygon)
        coords = GeoJSON.coordinates(poly)
        return is_point_inside_coords(pt, coords[1])
    elseif isa(poly, GeoJSON.MultiPolygon)
        for p_coords in GeoJSON.coordinates(poly)
            if is_point_inside_coords(pt, p_coords[1])
                return true
            end
        end
        return false
    end
    return false
end

function is_point_inside_coords(pt, coords)
    # PolygonOps.inpolygon returns 1 (inside), 0 (boundary), -1 (outside) by default?
    # We force explicit return values to be safe: in=1, on=1, out=0
    return PolygonOps.inpolygon(pt, coords, in=1, on=1, out=0) == 1
end

"""
    generate_agent_locations(topology::NetworkTopology, num_agents::Int)

Generates a list of agent locations.
Returns Vector{GeoPoint}.
"""
function generate_agent_locations(topology::NetworkTopology, num_agents::Int)
    @info "Generating locations for $num_agents agents..."
    locations = Vector{GeoPoint}(undef, num_agents)
    
    for i in 1:num_agents
        locations[i] = select_agent_location(topology)
    end
    @debug "Agent locations generated."
    return locations
end

end
