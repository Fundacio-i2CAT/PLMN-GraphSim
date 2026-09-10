using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.DataLoading
using DesJulia6gRupa.Types
import ConcurrentSim
using Random

@testset "Integration Tests (End-to-End)" begin

    @testset "Seeded topology deployment is reproducible" begin
        mktempdir() do data_dir
            csv_path = joinpath(data_dir, "cells.csv")
            open(csv_path, "w") do io
                for i in 1:12
                    println(io, "LTE,214,7,1,$i,0,$(-4.0 + i / 10),$(36.0 + i / 10),100,1,1,0,0,-80")
                end
            end
            config = SimConfig(1, 2, 1000, 1.0, 1.0, 1.0, :two_tier, 2, 1.0)
            Random.seed!(42)
            first = load_and_deploy_network([csv_path], 7, 3, data_dir, config)
            Random.seed!(42)
            second = load_and_deploy_network([csv_path], 7, 3, data_dir, config)

            @test first.upf_locations == second.upf_locations
            @test first.gnb_to_upf_map == second.gnb_to_upf_map
            @test first.centralized_upf_locations == second.centralized_upf_locations
            @test first.edge_upf_parent_map == second.edge_upf_parent_map
        end
    end

    # Define paths relative to this test file
    # Assuming test is run from project root or test/ folder
    # We need absolute paths to be safe
    project_root = dirname(dirname(@__FILE__))
    data_dir_spain = joinpath(project_root, "data", "spain")
    data_dir_usa = joinpath(project_root, "data", "usa")

    # Config for short simulation
    sim_config = SimConfig(1, 2, 10000, 1.0, 20.0, 5.0, :single_tier, 0, 1.0) # High scale factor = few agents, Short duration

    @testset "Spain Simulation (Movistar)" begin
        csv_path = joinpath(data_dir_spain, "opencellid", "214.csv")
        if isfile(csv_path)
            # 1. Load Network
            topology = load_and_deploy_network([csv_path], 7, 3, data_dir_spain, sim_config)
            @test length(topology.gnb_locations) > 0
            @test length(topology.upf_locations) == 3
            @test length(topology.municipalities) > 0

            # 2. Run Simulation (Manual steps to avoid full runner overhead)
            sim = ConcurrentSim.Simulation()
            global_state = init_global_state_for_simulation(topology, sim_config)
            
            # Just check initialization
            @test length(global_state.upf_sessions_5g) == 3
            @test length(global_state.forwarding_tables_6grupa) == 3
        else
            @warn "Spain data not found, skipping integration test."
        end
    end

    @testset "USA Simulation (Verizon)" begin
        csv_path = joinpath(data_dir_usa, "opencellid", "311.csv")
        if isfile(csv_path)
            # 1. Load Network
            # Verizon ID is 480
            topology = load_and_deploy_network([csv_path], 480, 3, data_dir_usa, sim_config)
            @test length(topology.gnb_locations) > 0
            @test length(topology.upf_locations) == 3
            @test length(topology.municipalities) > 0

            # 2. Run Simulation
            sim = ConcurrentSim.Simulation()
            global_state = init_global_state_for_simulation(topology, sim_config)
            
            # Just check initialization
            @test length(global_state.upf_sessions_5g) == 3
            @test length(global_state.forwarding_tables_6grupa) == 3
        else
            @warn "USA data not found, skipping integration test."
        end
    end

end
