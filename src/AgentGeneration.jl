module AgentGeneration

using ..Types
using Random
using GeometryBasics
using PolygonOps

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

function select_point_in_polygon(muni::Municipality)
    # Rejection Sampling
    # Define search box based on area approximation (expanded)
    area_m2 = muni.area * 10000.0
    radius_meters = max(sqrt(area_m2 / pi), 500.0)
    radius_deg = radius_meters / 111000.0
    
    # Expand box significantly (4x radius) to cover irregular shapes
    search_radius = 4.0 * radius_deg
    
    min_lon = muni.location.lon - search_radius
    max_lon = muni.location.lon + search_radius
    min_lat = muni.location.lat - search_radius
    max_lat = muni.location.lat + search_radius
    
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
        # We assume coordinates(poly) gives us something iterable of points
        coords = coordinates(poly)
        
        # PolygonOps.inpolygon returns 1 (inside), 0 (boundary), -1 (outside)
        # We consider boundary as inside
        return PolygonOps.inpolygon(pt, coords) >= 0
        
    elseif isa(poly, GeometryBasics.MultiPolygon)
        for p in poly
            if is_point_inside(pt, p)
                return true
            end
        end
        return false
    end
    return false
end

"""
    generate_agent_locations(topology::NetworkTopology, num_agents::Int)

Generates a list of agent locations.
Returns Vector{GeoPoint}.
"""
function generate_agent_locations(topology::NetworkTopology, num_agents::Int)
    locations = Vector{GeoPoint}(undef, num_agents)
    
    for i in 1:num_agents
        locations[i] = select_agent_location(topology)
    end
    
    return locations
end

end
