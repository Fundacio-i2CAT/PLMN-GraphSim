using Test
using PLMNGraphSim
using PLMNGraphSim.Types
using PLMNGraphSim.DataLoading
using PLMNGraphSim.Simulation
using Graphs
using MetaGraphsNext

@testset "Two-Tier Architecture Tests" begin

    @testset "Configuration" begin
        # Test default values
        config_default = SimConfig(1, 2, 1000, 10.0, 20.0, 5.0, :single_tier, 0, 1.0)
        @test config_default.scenario == :single_tier
        @test config_default.num_centralized_upfs == 0

        # Test two-tier values
        config_two_tier = SimConfig(1, 2, 1000, 10.0, 20.0, 5.0, :two_tier, 5, 1.0)
        @test config_two_tier.scenario == :two_tier
        @test config_two_tier.num_centralized_upfs == 5
    end

    @testset "Hierarchical Clustering" begin
        # Create mock Edge UPFs
        # 3 close to (0,0), 3 close to (10,10)
        edge_upfs = [
            GeoPoint(0.0, 0.0), GeoPoint(0.1, 0.1), GeoPoint(0.0, 0.1),
            GeoPoint(10.0, 10.0), GeoPoint(10.1, 10.1), GeoPoint(10.0, 10.1)
        ]
        
        # Cluster into 2 Centralized UPFs
        centralized_locs, mapping = PLMNGraphSim.DataLoading.perform_hierarchical_clustering(edge_upfs, 2)
        
        @test length(centralized_locs) == 2
        @test length(mapping) == 6
        
        # Check assignments (first 3 should be same cluster, last 3 same cluster)
        @test mapping[1] == mapping[2] == mapping[3]
        @test mapping[4] == mapping[5] == mapping[6]
        @test mapping[1] != mapping[4]
    end

    @testset "Graph Construction (Two-Tier)" begin
        # Mock Data
        gnb_locs = [GeoPoint(0.0, 0.0)]
        edge_upf_locs = [GeoPoint(1.0, 1.0)]
        gnb_to_upf = [1]
        
        centralized_locs = [GeoPoint(2.0, 2.0)]
        edge_to_centralized = [1]
        
        mg = PLMNGraphSim.DataLoading.build_graph(edge_upf_locs, gnb_locs, gnb_to_upf, centralized_locs, edge_to_centralized)
        
        # Check Nodes
        @test haskey(mg, (:gNB, 1))
        @test haskey(mg, (:UPF, 1))
        @test haskey(mg, (:CentralizedUPF, 1))
        
        # Check Edges
        # gNB -> Edge UPF
        u = (:gNB, 1)
        v = (:UPF, 1)
        @test has_edge(mg, code_for(mg, u), code_for(mg, v))
        
        # Edge UPF -> Centralized UPF
        u2 = (:UPF, 1)
        v2 = (:CentralizedUPF, 1)
        @test has_edge(mg, code_for(mg, u2), code_for(mg, v2))
    end

    @testset "Routing Logic" begin
        # Mock Topology
        graph = MetaGraph(Graph(), label_type = Tuple{Symbol, Int}, vertex_data_type = GeoPoint, edge_data_type = Float64)
        add_vertex!(graph, (:UPF, 1), GeoPoint(0.0, 0.0))
        add_vertex!(graph, (:CentralizedUPF, 1), GeoPoint(1.0, 1.0))
        
        topology = NetworkTopology(
            GeoPoint[], 
            [GeoPoint(0.0, 0.0)], # 1 Edge UPF
            Int[], 
            [GeoPoint(1.0, 1.0)], # 1 Centralized UPF
            [1],      # Edge 1 -> Centralized 1
            Municipality[], 
            Dict{String,Vector{Int}}(), 
            Float64[], 
            graph
        )

        # Test Edge UPF Routing (Should have default route to PSA)
        forwarding_tables = Simulation.init_state_6g_rupa(topology)
        @test length(forwarding_tables) == 1
        table = forwarding_tables[1]
        # Should have default route
        default_route = findfirst(e -> e.dest_prefix == 0 && e.mask == 0, table)
        @test !isnothing(default_route)
        @test table[default_route].output_interface == 2 # Uplink

        # Test Centralized UPF Routing (Should have route to Edge UPF)
        centralized_tables = Simulation.init_centralized_state_6g_rupa(topology)
        @test length(centralized_tables) == 1
        c_table = centralized_tables[1]
        # Should have route to Edge UPF 1
        edge_route = findfirst(e -> e.dest_prefix == 1, c_table) # Assuming dest_prefix is edge index
        @test !isnothing(edge_route)
        @test c_table[edge_route].output_interface == 1
    end

    @testset "Session Context (Anchor Assignment)" begin
        # Mock Topology with Parent Map
        topology = NetworkTopology(
            GeoPoint[], 
            [GeoPoint(0.0, 0.0)], 
            Int[], 
            [GeoPoint(1.0, 1.0)], 
            [1], # Edge 1 -> Centralized 1
            Municipality[], 
            Dict{String,Vector{Int}}(), 
            Float64[], 
            MetaGraph(Graph(), label_type = Tuple{Symbol, Int}, vertex_data_type = GeoPoint, edge_data_type = Float64)
        )

        # Create session for user served by Edge UPF 1
        ctx = Simulation.create_session_context(1, topology)
        
        @test ctx.metadata.serving_upf_index == 1
        @test ctx.metadata.anchor_upf_index == 1 # It should be 1 because edge_upf_parent_map[1] == 1
        
        # Test Single Tier Fallback (Empty parent map)
        topology_single = NetworkTopology(
            GeoPoint[], [GeoPoint(0.0, 0.0)], Int[], GeoPoint[], Int[], 
            Municipality[], Dict{String,Vector{Int}}(), Float64[], 
            MetaGraph(Graph(), label_type = Tuple{Symbol, Int}, vertex_data_type = GeoPoint, edge_data_type = Float64)
        )
        ctx_single = Simulation.create_session_context(1, topology_single)
        @test ctx_single.metadata.serving_upf_index == 1
        @test ctx_single.metadata.anchor_upf_index == 1 # Should match serving
    end

    @testset "Session Registration (Two-Tier)" begin
        # Mock Topology
        topology = NetworkTopology(
            GeoPoint[], 
            [GeoPoint(0.0, 0.0)], # 1 Edge UPF
            Int[], 
            [GeoPoint(1.0, 1.0)], # 1 Centralized UPF
            [1],      # Edge 1 -> Centralized 1
            Municipality[], 
            Dict{String,Vector{Int}}(), 
            Float64[], 
            MetaGraph(Graph(), label_type = Tuple{Symbol, Int}, vertex_data_type = GeoPoint, edge_data_type = Float64)
        )
        
        config = SimConfig(1, 1, 1000, 10.0, 20.0, 5.0, :two_tier, 1, 1.0)
        
        # Init State
        state = Simulation.init_global_state_for_simulation(topology, config)
        
        # Check initial size
        # 1 Edge + 1 Centralized = 2 slots
        @test length(state.upf_sessions_5g) == 2
        @test isempty(state.upf_sessions_5g[1])
        @test isempty(state.upf_sessions_5g[2])
        
        # Create Connections
        # Assigned UPF = 1 (Edge)
        Simulation.create_random_ue_connections(state, 1, topology)
        
        # Should have 1 session in Edge UPF (Index 1)
        @test length(state.upf_sessions_5g[1]) == 1
        
        # Should NOT have session in Centralized UPF (Index 2) - UEs only connect to Tier 1
        @test isempty(state.upf_sessions_5g[2])
        
        # Verify metadata points to correct anchor
        ctx_edge = state.upf_sessions_5g[1][1]
        @test ctx_edge.metadata.serving_upf_index == 1
        @test ctx_edge.metadata.anchor_upf_index == 1
        
        # Test Metrics Calculation (to ensure PSA load is derived)
        metrics = Simulation.collect_5g_metrics(state, topology, 1)
        
        # Edge UPF (Index 1) should have 2 entries (UL + DL)
        @test metrics.per_upf_entries[1] == 2
        
        # PSA UPF (Index 2) should have 2 entries (derived UL + DL)
        @test metrics.per_upf_entries[2] == 2
        
        # Release Connections
        Simulation.release_ue_connections(state, 1, 1)
        
        @test isempty(state.upf_sessions_5g[1])
        @test isempty(state.upf_sessions_5g[2])
    end
end
