# Step definitions for handover classification feature

using Test
using DesJulia6gRupa
using DesJulia6gRupa.Types
using DesJulia6gRupa.Simulation

# Test context struct
mutable struct TestContext
    sim_state::SimGlobalState
    topology::NetworkTopology
    agent_sessions_5g::Vector{SessionContext5G}
    agent_sessions_6grupa::Vector{ForwardingEntry6GRUPA}
    gnb_1_id::Int
    gnb_2_id::Int
    gnb_3_id::Int
    upf_1_id::Int
    upf_2_id::Int
    gupf_1_id::Int
    gupf_2_id::Int
    architecture::Symbol
end

function setup_single_mno_two_upfs()::TestContext
    config = SimConfig(10, 100, 1000, 100.0, 30.0, 5.0, :basic, 0, 1.0)

    gnb_locs = [GeoPoint(40.0, -74.0), GeoPoint(40.1, -74.1), GeoPoint(40.2, -74.2)]
    upf_locs = [GeoPoint(40.05, -74.05), GeoPoint(40.15, -74.15)]
    gnb_to_upf = [1, 1, 2]

    topology = NetworkTopology(
        gnb_locs, upf_locs, gnb_to_upf,
        [], [], [], Dict(), []
    )

    sim_state = SimGlobalState(
        config,
        [[], []],
        [[], []],
        [],
        [], [], [], [], []
    )

    metadata = SessionSimMetadata(1, 1, 1, 1)
    fwd_state = ForwardingState5G(rand(UInt32), rand(UInt32), FAR(0, 0), FAR(0, 0))
    session = SessionContext5G(fwd_state, metadata)
    agent_sessions = [session]

    ctx = TestContext(sim_state, topology, agent_sessions, [], 1, 2, 3, 1, 2, 1, 2, Symbol("5g"))
    return ctx
end

function when_xn_handover(ctx::TestContext)
    old_upf = 1
    new_upf = 1
    old_domain = 1
    new_domain = 1
    old_operator = 1
    new_operator = 1

    handle_handover_5g!(ctx.sim_state, ctx.topology, ctx.agent_sessions_5g,
                        old_upf, new_upf, old_domain, new_domain, old_operator, new_operator)
end

function when_n2_handover(ctx::TestContext)
    old_upf = 1
    new_upf = 2
    old_domain = 1
    new_domain = 2
    old_operator = 1
    new_operator = 1

    handle_handover_5g!(ctx.sim_state, ctx.topology, ctx.agent_sessions_5g,
                        old_upf, new_upf, old_domain, new_domain, old_operator, new_operator)
end

function when_roaming_handover_5g(ctx::TestContext)
    old_upf = 1
    new_upf = 2
    old_domain = 1
    new_domain = 1
    old_operator = 1
    new_operator = 2

    handle_handover_5g!(ctx.sim_state, ctx.topology, ctx.agent_sessions_5g,
                        old_upf, new_upf, old_domain, new_domain, old_operator, new_operator)
end
