function initialize_graph()
    # We use MetaGraph with Tuple labels: (:gNB, id), (:UPF, id), (:Agent, id)
    # Vertex Data: GeoPoint
    # Edge Data: Distance/Latency (Float64) in Kilometers
    return MetaGraph(
        Graph(), # Underlying graph
        label_type=Tuple{Symbol,Int}, # Vertex Label Type
        vertex_data_type=GeoPoint, # Vertex Data Type
        edge_data_type=Float64 # Edge Data Type (Distance in km)
    )
end

function add_upf_nodes!(mg, upf_locs::Vector{GeoPoint})
    for (i, loc) in enumerate(upf_locs)
        add_vertex!(mg, (:UPF, i), loc)
    end
end

function add_gnb_nodes_and_edges!(mg, gnb_points::Vector{GeoPoint}, upf_locs::Vector{GeoPoint}, gnb_to_upf::Vector{Int})
    for (i, loc) in enumerate(gnb_points)
        add_vertex!(mg, (:gNB, i), loc)

        # Connect to assigned UPF
        upf_idx = gnb_to_upf[i]

        # Calculate distance
        upf_loc = upf_locs[upf_idx]
        dist_km = haversine_distance(loc, upf_loc)

        add_edge!(mg, (:gNB, i), (:UPF, upf_idx), dist_km)
    end
end

function add_centralized_upf_nodes_and_edges!(mg, centralized_upf_locs::Vector{GeoPoint}, edge_upf_locs::Vector{GeoPoint}, edge_upf_parent_map::Vector{Int})
    # Add Centralized UPF Nodes
    for (i, loc) in enumerate(centralized_upf_locs)
        add_vertex!(mg, (:CentralizedUPF, i), loc)
    end

    # Add Edges between Edge UPFs and Centralized UPFs (N9 Interface)
    for (edge_idx, parent_idx) in enumerate(edge_upf_parent_map)
        edge_loc = edge_upf_locs[edge_idx]
        parent_loc = centralized_upf_locs[parent_idx]
        dist_km = haversine_distance(edge_loc, parent_loc)
        
        add_edge!(mg, (:UPF, edge_idx), (:CentralizedUPF, parent_idx), dist_km)
    end
end

function build_graph(upf_locs::Vector{GeoPoint}, gnb_points::Vector{GeoPoint}, gnb_to_upf::Vector{Int}, 
                     centralized_upf_locs::Vector{GeoPoint} = Vector{GeoPoint}(), 
                     edge_upf_parent_map::Vector{Int} = Vector{Int}())
    @info "Building Network Graph with $(length(upf_locs)) UPFs and $(length(gnb_points)) gNBs..."
    mg = initialize_graph()
    add_upf_nodes!(mg, upf_locs)
    add_gnb_nodes_and_edges!(mg, gnb_points, upf_locs, gnb_to_upf)
    
    if !isempty(centralized_upf_locs)
        @info "Adding $(length(centralized_upf_locs)) Centralized UPFs to the graph..."
        add_centralized_upf_nodes_and_edges!(mg, centralized_upf_locs, upf_locs, edge_upf_parent_map)
    end

    @debug "Graph built successfully with $(nv(mg)) vertices and $(ne(mg)) edges."
    return mg
end
