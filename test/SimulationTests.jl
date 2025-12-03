using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.Types
using Graphs
using MetaGraphsNext

@testset "Simulation Logic Tests" begin

    @testset "find_serving_gnb" begin
        # Mock Topology with just gNB locations
        gnb_locs = [
            GeoPoint(0.0, 0.0),   # Index 1
            GeoPoint(10.0, 0.0),  # Index 2
            GeoPoint(0.0, 10.0)   # Index 3
        ]
        
        # Create a minimal mock topology (other fields can be empty/dummy)
        mock_topology = NetworkTopology(
            gnb_locs,
            GeoPoint[], # upf_locations
            Int[],      # gnb_to_upf_map
            GeoPoint[], # centralized_upf_locations
            Int[],      # edge_upf_parent_map
            Municipality[], # municipalities
            Dict{String,Vector{Int}}(), # municipality_bins
            Float64[], # municipality_probs
            MetaGraph(Graph(), label_type = Tuple{Symbol, Int}, vertex_data_type = GeoPoint, edge_data_type = Float64) # graph
        )

        # Test Case 1: User exactly at gNB 1
        user1 = GeoPoint(0.0, 0.0)
        @test Simulation.find_serving_gnb(mock_topology, user1) == 1

        # Test Case 2: User closer to gNB 2 (5.1, 0.0) -> dist to 1 is 5.1, to 2 is 4.9
        user2 = GeoPoint(5.1, 0.0)
        @test Simulation.find_serving_gnb(mock_topology, user2) == 2

        # Test Case 3: User closer to gNB 3 (0.0, 6.0) -> dist to 1 is 6.0, to 3 is 4.0
        user3 = GeoPoint(0.0, 6.0)
        @test Simulation.find_serving_gnb(mock_topology, user3) == 3
    end

    @testset "init_state_5g" begin
        num_upfs = 5
        state_5g = Simulation.init_state_5g(num_upfs)
        
        @test length(state_5g) == num_upfs
        @test all(isempty, state_5g)
        @test eltype(state_5g) == Vector{SessionContext5G}
    end

    @testset "init_state_6g_rupa" begin
        # Construct a Mock Graph
        # 1 UPF connected to 2 gNBs
        # UPF ID: 1
        # gNB IDs: 10, 20
        
        graph = MetaGraph(Graph(), label_type = Tuple{Symbol, Int}, vertex_data_type = GeoPoint, edge_data_type = Float64)
        
        # Add Vertices
        upf_label = (:UPF, 1)
        gnb1_label = (:gNB, 10)
        gnb2_label = (:gNB, 20)
        
        add_vertex!(graph, upf_label, GeoPoint(0.0, 0.0))
        add_vertex!(graph, gnb1_label, GeoPoint(1.0, 0.0))
        add_vertex!(graph, gnb2_label, GeoPoint(0.0, 1.0))
        
        # Add Edges (UPF <-> gNB)
        add_edge!(graph, upf_label, gnb1_label, 1.0)
        add_edge!(graph, upf_label, gnb2_label, 1.0)
        
        # Create Mock Topology
        mock_topology = NetworkTopology(
            GeoPoint[], 
            [GeoPoint(0.0, 0.0)], # 1 UPF
            Int[], 
            GeoPoint[], # centralized_upf_locations
            Int[],      # edge_upf_parent_map
            Municipality[], 
            Dict{String,Vector{Int}}(), 
            Float64[], 
            graph
        )
        
        # Run Initialization
        forwarding_tables = Simulation.init_state_6g_rupa(mock_topology)
        
        # Assertions
        @test length(forwarding_tables) == 1 # 1 UPF
        table = forwarding_tables[1]
        
        @test length(table) == 2 # Should have 2 entries (one for each gNB)
        
        # Check content of entries
        dest_prefixes = [entry.dest_prefix for entry in table]
        @test 10 in dest_prefixes
        @test 20 in dest_prefixes
        
        # Check other fields
        @test table[1].mask == 0xFFFFFF00
        @test table[1].output_interface == 1
    end

    @testset "save_detailed_evolution" begin
        # Mock Config
        config = SimConfig(1, 2, 1000, 10.0, 5.0, 5.0, :single_tier, 0, 1.0)

        # Mock State
        state = SimGlobalState(
            config,
            [[SessionContext5G(ForwardingState5G(1, 1, FAR(1, 1), FAR(1, 1)), SessionSimMetadata(1, 1))]], # 1 UPF, 1 Session
            [[ForwardingEntry6GRUPA(10, 0xFFFFFF00, 1)]],     # 1 UPF, 1 Entry
            Vector{ForwardingEntry6GRUPA}[], # centralized_forwarding_tables_6grupa
            [1.0], # history_time
            [[10.0]], # history_per_upf_5g_fwd_state_info_size_mb
            [[100]],  # history_per_upf_entries_5g
            [[5.0]],  # history_per_gupf_6grupa_fwd_state_info_size_mb
            [[50]]    # history_per_gupf_entries_6grupa
        )
        
        # Mock Topology
        mock_topology = NetworkTopology(
            GeoPoint[], 
            [GeoPoint(0.0, 0.0)], # 1 UPF
            Int[], 
            GeoPoint[], # centralized_upf_locations
            Int[],      # edge_upf_parent_map
            Municipality[], 
            Dict{String,Vector{Int}}(), 
            Float64[], 
            MetaGraph(Graph(), label_type = Tuple{Symbol, Int}, vertex_data_type = GeoPoint, edge_data_type = Float64)
        )
        
        mktempdir() do temp_dir
            operator_name = "TestOp"
            scenario_name = "TestScenario"
            
            Simulation.save_detailed_evolution(operator_name, scenario_name, state, mock_topology, temp_dir)
            
            @test isfile(joinpath(temp_dir, "evolution_5g_fwd_state_info_size_mb_TestOp_TestScenario.csv"))
            @test isfile(joinpath(temp_dir, "evolution_5g_entries_TestOp_TestScenario.csv"))
            @test isfile(joinpath(temp_dir, "evolution_6grupa_mb_TestOp_TestScenario.csv"))
            @test isfile(joinpath(temp_dir, "evolution_6grupa_entries_TestOp_TestScenario.csv"))
        end
    end

end
