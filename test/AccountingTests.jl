using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.Types

if !isdefined(Main, :TestFixtures)
    include("TestFixtures.jl")
end
using .TestFixtures

# Billing orthogonality (§7.3), the CODE-observable half: under SSC mode 1 the
# PSA is pinned intra-PLMN, so the URR (charging context) never relocates —
# acct_reloc is 0 for BOTH architectures at every routine level, including a
# PSA-region crossing. (5G accounting relocation arises only on SSC2/3 re-anchor
# or Home-Routed roaming, exercised in RoamingTests.)
#
# The other half of the claim — identical per-flow billing granularity, RUPA's
# key being identity-bound vs 5G's location-bound — is an ANALYTIC argument about
# record keys, not a property of this simulator's code; it lives in the paper and
# in test/features/handover_classification.feature ("Same granularity, different
# key"), not as a self-contained ledger asserted here.
@testset "Billing orthogonality — no accounting churn intra-PLMN (SSC-1)" begin
    topology = two_psa_topology()
    scale = 1000
    config = SimConfig(1, 1, scale, 10.0, 5.0, 5.0, :two_tier, 2, 1.0,
                       MobilityConfig(true, 1.0, RandomWaypoint(5.0, 0.0, 1.0)))
    state = Simulation.init_global_state_for_simulation(topology, config)
    ctx = Simulation.create_session_context(1, topology)
    push!(state.upf_sessions_5g[1], ctx); sessions = [ctx]

    # L1 (same edge), L2 (same PSA), L2 (cross-PSA region) — none relocate the anchor.
    sessions = Simulation.dispatch_handover!(state, topology, sessions, 1, 2, 1, 1, 1, 1, 1, 1)
    sessions = Simulation.dispatch_handover!(state, topology, sessions, 2, 3, 1, 2, 1, 2, 1, 1)
    sessions = Simulation.dispatch_handover!(state, topology, sessions, 3, 4, 2, 3, 2, 3, 1, 1)
    @test state.acct_reloc_5g == 0
    @test state.acct_reloc_rupa == 0
    @test sessions[1].metadata.anchor_upf_index == 1   # PSA pinned throughout
end
