"""
Test-Driven Development for Handover Classification and Signaling Cost Tracking

Executes the Gherkin scenarios from features/handover_classification.feature
as executable Julia tests. Tests drive the implementation: run tests first (they fail),
then implement to make them pass.

Run with: julia --project test/test_handover_classification.jl
"""

using Test
include("steps/handover_steps.jl")

@testset "Handover Classification and Signaling Costs" begin

    @testset "Scenario: Xn handover (same anchor UPF)" begin
        ctx = setup_single_mno_two_upfs()
        ctx.sim_state.upf_sessions_5g[1] = [ctx.agent_sessions_5g[1]]

        # When: Xn handover
        when_xn_handover(ctx)

        # Then: Classification and counters
        then_xn_classification(ctx)
        then_handover_count_increments(ctx)
        @test ctx.sim_state.sigma_5g_xn == 500
    end

    @testset "Scenario: N2 handover (anchor UPF changes)" begin
        ctx = setup_single_mno_two_upfs()
        ctx.sim_state.upf_sessions_5g[1] = [ctx.agent_sessions_5g[1]]

        # When: N2 handover
        when_n2_handover(ctx)

        # Then: Classification and counters
        then_n2_classification(ctx)
        then_handover_count_increments(ctx)
        @test ctx.sim_state.sigma_5g_n2 == 1080
    end

    @testset "Scenario: 5G Home-Routed roaming" begin
        ctx = setup_single_mno_two_upfs()
        ctx.sim_state.upf_sessions_5g[1] = [ctx.agent_sessions_5g[1]]

        # When: Roaming handover
        when_roaming_handover_5g(ctx)

        # Then: Roaming classification
        then_roaming_classification_5g(ctx)
        then_handover_count_increments(ctx)
        @test ctx.sim_state.sigma_roam_5g == 1180
    end

    @testset "Scenario: 6G-RUPA intra-domain handover" begin
        ctx = setup_single_mno_two_upfs()
        ctx.architecture = :6grupa

        # When: Intra-domain renumbering (same GUPF)
        old_gnb = 1
        new_gnb = 2
        old_domain = 1
        new_domain = 1
        old_operator = 1
        new_operator = 1

        handle_handover_6grupa!(ctx.sim_state, ctx.topology,
                                old_gnb, new_gnb,
                                old_domain, new_domain,
                                old_operator, new_operator)

        # Then: Intra-domain classification
        @test ctx.sim_state.sigma_rupa_intra == 200 "Intra-domain should be 200 bytes"
        @test ctx.sim_state.sigma_rupa_inter == 0 "Inter-domain should not change"
        @test ctx.sim_state.handover_count == 1
    end

    @testset "Scenario: 6G-RUPA inter-domain handover" begin
        ctx = setup_single_mno_two_upfs()
        ctx.architecture = :6grupa

        # When: Inter-domain renumbering (different GUPF)
        old_gnb = 1
        new_gnb = 3
        old_domain = 1
        new_domain = 2
        old_operator = 1
        new_operator = 1

        handle_handover_6grupa!(ctx.sim_state, ctx.topology,
                                old_gnb, new_gnb,
                                old_domain, new_domain,
                                old_operator, new_operator)

        # Then: Inter-domain classification
        @test ctx.sim_state.sigma_rupa_inter == 400 "Inter-domain should be 400 bytes"
        @test ctx.sim_state.sigma_rupa_intra == 0 "Intra-domain should not change"
        @test ctx.sim_state.handover_count == 1
    end

    @testset "Scenario: 6G-RUPA inter-layer roaming" begin
        ctx = setup_single_mno_two_upfs()
        ctx.architecture = :6grupa

        # When: Roaming handover (operator change)
        old_gnb = 1
        new_gnb = 3
        old_domain = 1
        new_domain = 1  # Same domain in visited layer
        old_operator = 1  # Home layer
        new_operator = 2  # Visited layer (satellite)

        handle_handover_6grupa!(ctx.sim_state, ctx.topology,
                                old_gnb, new_gnb,
                                old_domain, new_domain,
                                old_operator, new_operator)

        # Then: Roaming classification
        @test ctx.sim_state.sigma_roam_rupa == 300 "Inter-layer roaming should be 300 bytes"
        @test ctx.sim_state.handover_count == 1
    end

    @testset "Scenario: History tracking" begin
        ctx = setup_single_mno_two_upfs()
        ctx.sim_state.upf_sessions_5g[1] = [ctx.agent_sessions_5g[1]]

        # Multiple handovers of different types
        when_xn_handover(ctx)      # sigma_5g_xn = 500
        when_xn_handover(ctx)      # sigma_5g_xn = 1000
        when_n2_handover(ctx)      # sigma_5g_n2 = 1080

        # Then: Counters track correctly
        @test ctx.sim_state.sigma_5g_xn == 1000 "Two Xn handovers = 1000 bytes"
        @test ctx.sim_state.sigma_5g_n2 == 1080 "One N2 handover = 1080 bytes"
        @test ctx.sim_state.handover_count == 3 "Total 3 handovers"
    end

end

println("All tests passed! TDD cycle complete for this iteration.")
