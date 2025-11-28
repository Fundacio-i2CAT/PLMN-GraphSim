module AgentGeneration

using ..Types
using Random

export select_agent_location, generate_agent_locations

"""
    select_agent_location(topology::NetworkTopology)

Selects a random location for an agent based on the population distribution
defined in the topology (Province-based probabilities).
Returns a tuple (GeoPoint, gnb_index).
"""
function select_agent_location(topology::NetworkTopology)
    # 1. Select Province based on Population Probability
    r = rand()
    cumulative = 0.0
    selected_province = ""
    
    for (i, prob) in enumerate(topology.province_probs)
        cumulative += prob
        if r <= cumulative
            selected_province = topology.province_names[i]
            break
        end
    end
    
    # Fallback
    if selected_province == "" && !isempty(topology.province_names)
        selected_province = topology.province_names[end]
    end

    # 2. Select gNB within that Province
    gnb_idx = 1
    if selected_province != "" && haskey(topology.province_bins, selected_province)
        candidates = topology.province_bins[selected_province]
        if !isempty(candidates)
            gnb_idx = rand(candidates)
        else
            # Fallback to global random if bin is empty
            gnb_idx = rand(1:length(topology.gnb_locations))
        end
    else
        gnb_idx = rand(1:length(topology.gnb_locations))
    end
    
    gnb = topology.gnb_locations[gnb_idx]
    
    # 3. Add Jitter (approx 1-2km)
    # 0.02 degrees is roughly 2km
    jitter_lon = (rand() - 0.5) * 0.02 
    jitter_lat = (rand() - 0.5) * 0.02
    
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
