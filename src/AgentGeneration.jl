module AgentGeneration

using ..Types
using Random

export select_agent_location, generate_agent_locations

"""
    select_agent_location(topology::NetworkTopology)

Selects a random location for an agent based on the population distribution.
Uses Municipality-based distribution.
Returns a tuple (GeoPoint, gnb_index).
"""
function select_agent_location(topology::NetworkTopology)
    # Check if we have granular municipality data
    if !isempty(topology.municipalities) && !isempty(topology.municipality_probs)
        return select_agent_location_municipality(topology)
    else
        # Fallback to purely random if no municipality data (should not happen if setup is correct)
        gnb_idx = rand(1:length(topology.gnb_locations))
        gnb = topology.gnb_locations[gnb_idx]
        
        jitter_lon = (rand() - 0.5) * 0.02 
        jitter_lat = (rand() - 0.5) * 0.02
        
        return GeoPoint(gnb.lat + jitter_lat, gnb.lon + jitter_lon), gnb_idx
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
    
    # 2. Select gNB within that Municipality
    gnb_idx = 1
    if haskey(topology.municipality_bins, muni.code)
        candidates = topology.municipality_bins[muni.code]
        if !isempty(candidates)
            gnb_idx = rand(candidates)
        else
            # Should not happen due to filtering in DataLoading, but safe fallback
            gnb_idx = rand(1:length(topology.gnb_locations))
        end
    else
        gnb_idx = rand(1:length(topology.gnb_locations))
    end
    
    gnb = topology.gnb_locations[gnb_idx]
    
    # 3. Add Jitter
    # We can be smarter here: Jitter based on Municipality Area?
    # Area is in hectares. 1 hectare = 0.01 km2. Sqrt(Area) ~ side length in 100m units.
    # Let's stick to simple jitter for now to avoid placing users too far from gNB coverage.
    # 0.01 degrees is roughly 1km.
    jitter_lon = (rand() - 0.5) * 0.015 
    jitter_lat = (rand() - 0.5) * 0.015
    
    return GeoPoint(gnb.lat + jitter_lat, gnb.lon + jitter_lon), gnb_idx
end

"""
    generate_agent_locations(topology::NetworkTopology, num_agents::Int)

Generates a list of agent locations and their assigned gNB indices.
Returns (Vector{GeoPoint}, Vector{Int}).
"""
function generate_agent_locations(topology::NetworkTopology, num_agents::Int)
    locations = Vector{GeoPoint}(undef, num_agents)
    gnb_indices = Vector{Int}(undef, num_agents)
    
    for i in 1:num_agents
        loc, idx = select_agent_location(topology)
        locations[i] = loc
        gnb_indices[i] = idx
    end
    
    return locations, gnb_indices
end

end
