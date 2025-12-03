using Test
using GeometryBasics
using PolygonOps
using Graphs
using MetaGraphsNext
using GeoJSON
using JSON3

# Assuming we are running from project root
using DesJulia6gRupa
using DesJulia6gRupa.Types
using DesJulia6gRupa.AgentGeneration

@testset "AgentGeneration Tests" begin

    @testset "GeoPoint and Distance" begin
        p1 = GeoPoint(0.0, 0.0)
        p2 = GeoPoint(0.0, 1.0)
        # 1 degree longitude at equator is approx 111km
        dist = haversine_distance(p1, p2)
        @test 110.0 < dist < 112.0
    end

    @testset "Point in Circle" begin
        # Create a dummy municipality
        # Area 100 hectares -> 1,000,000 m2 -> r = sqrt(1000000/pi) approx 564m
        muni = Municipality("001", "TestMuni", 1000, GeoPoint(40.0, -3.0), 100.0, nothing)
        
        for _ in 1:100
            pt = AgentGeneration.select_point_in_circle(muni)
            dist = haversine_distance(muni.location, pt)
            # Radius in km approx 0.564 km. 
            # The function uses max(sqrt(area/pi), 500.0)
            # 564m > 500m.
            # Allow some margin for calculation errors (1km is safe upper bound)
            @test dist < 1.0 
        end
    end

    @testset "Point in Polygon" begin
        # Create a simple square polygon
        # (0,0), (1,0), (1,1), (0,1)
        # Note: Coordinates in GeometryBasics are usually (x,y) -> (lon, lat)
        p1 = Point2(0.0, 0.0)
        p2 = Point2(1.0, 0.0)
        p3 = Point2(1.0, 1.0)
        p4 = Point2(0.0, 1.0)
        # PolygonOps requires closed polygon
        poly = Polygon([p1, p2, p3, p4, p1])
        
        # Test is_point_inside
        @test AgentGeneration.is_point_inside(Point2(0.5, 0.5), poly)
        @test !AgentGeneration.is_point_inside(Point2(1.5, 0.5), poly)
        
        # Test select_point_in_polygon
        # We need to mock the municipality location to be inside/near the polygon for the search box
        # Centroid approx (0.5, 0.5)
        muni_centered = Municipality("002", "PolyMuni", 1000, GeoPoint(0.5, 0.5), 10000.0, poly) # Large area to ensure search radius covers it
        
        pt = AgentGeneration.select_point_in_polygon(muni_centered)
        # Check if point is inside (0,0) to (1,1)
        @test 0.0 <= pt.lon <= 1.0
        @test 0.0 <= pt.lat <= 1.0
    end

    @testset "Point in GeoJSON Polygon" begin
        # Create a GeoJSON polygon string
        json_str = """{"type": "Polygon", "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]]}"""
        poly = GeoJSON.read(json_str)
        
        # Test is_point_inside
        @test AgentGeneration.is_point_inside(Point2(0.5, 0.5), poly)
        @test !AgentGeneration.is_point_inside(Point2(1.5, 0.5), poly)
        
        # Test select_point_in_polygon
        muni_centered = Municipality("003", "GeoJSONMuni", 1000, GeoPoint(0.5, 0.5), 10000.0, poly)
        
        pt = AgentGeneration.select_point_in_polygon(muni_centered)
        @test 0.0 <= pt.lon <= 1.0
        @test 0.0 <= pt.lat <= 1.0
    end

    @testset "Agent Selection Logic" begin
        # Mock Topology
        # 2 Municipalities
        m1 = Municipality("1", "M1", 100, GeoPoint(40.0, 0.0), 10.0, nothing)
        m2 = Municipality("2", "M2", 0, GeoPoint(41.0, 0.0), 10.0, nothing)

        # Probabilities: 100% M1, 0% M2
        probs = [1.0, 0.0]
        
        # Mock Graph (empty)
        mg = MetaGraph(Graph(), label_type=Tuple{Symbol, Int}, vertex_data_type=GeoPoint, edge_data_type=Float64)
        
        topo = NetworkTopology(
            Vector{GeoPoint}(), 
            Vector{GeoPoint}(), 
            Vector{Int}(), 
            Vector{GeoPoint}(), # centralized_upf_locations
            Vector{Int}(),      # edge_upf_parent_map
            [m1, m2], 
            Dict{String,Vector{Int}}(), 
            probs, 
            mg
        )
        # Generate 10 agents, all should be near M1 (lat 40)
        agents = generate_agent_locations(topo, 10)
        @test length(agents) == 10
        for a in agents
            @test 39.9 < a.lat < 40.1
        end
    end
end
