using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.Types
using Graphs
using MetaGraphsNext
using ConcurrentSim: ConcurrentSim, @process, Process

if !isdefined(Main, :TestFixtures)
    include("TestFixtures.jl")
end
using .TestFixtures

# Roaming (§7.4 of the mobility paper; constants derived in
# infocom-mobility-paper/notes/roaming-internetworking.md §4).
#
# Border-crossing event semantics (supervisor item B7a — both modelled):
#   :reestablish (deployed default): PLMN reselection + registration + NEW HR PDU
#     session (TS 23.122; TS 23.502 §4.2.2.2.2/§4.3.2.2.2). σ ≈ SIGMA_ROAM_5G_REEST B, the flow
#     BREAKS, and the charging context is rebuilt (accounting relocation).
#   :ideal_ho (5G best-case sensitivity): idealized connected-mode inter-PLMN N2
#     handover (~N2 1150 B + N32 envelope ≈ SIGMA_ROAM_5G_IDEAL B), session survives.
# 6G-RUPA: enrollment (~200) + flat renumber (200) + internetwork-DIF
# advertisement (~50) ≈ SIGMA_ROAM_RUPA B; the flow survives in BOTH semantics (EFCP keyed on
# port-ids, address is a synonym).

@testset "Roaming (§7.4)" begin

    # Tiny two-tier topology: 2 edge UPFs → 1 PSA, 2 gNBs.
    function _mini_topology()
        gnb_locs = [GeoPoint(0.0, 0.0), GeoPoint(0.1, 0.1)]
        upf_locs = [GeoPoint(0.0, 0.0), GeoPoint(0.1, 0.1)]
        return NetworkTopology(
            gnb_locs, upf_locs, [1, 2],
            [GeoPoint(0.05, 0.05)], [1, 1],
            Municipality[], Dict{String,Vector{Int}}(), Float64[],
            MetaGraph(Graph(), label_type = Tuple{Symbol, Int},
                      vertex_data_type = GeoPoint, edge_data_type = Float64),
        )
    end

    function _state(topology; scale = 1000, semantics = :reestablish)
        config = SimConfig(1, 2, scale, 10.0, 5.0, 5.0, :two_tier, 1, 1.0,
                           MobilityConfig(true, 1.0, RandomWaypoint(5.0, 0.0, 1.0)),
                           RoamingConfig(semantics, 0.0))
        return Simulation.init_global_state_for_simulation(topology, config)
    end

    @testset "RoamingConfig defaults preserve legacy behaviour" begin
        rc = RoamingConfig()
        @test rc.border_semantics == :reestablish
        @test rc.roamer_fraction == 0.0

        # Legacy constructors still work and default the roaming config.
        sc9 = SimConfig(1, 2, 1000, 10.0, 5.0, 5.0, :single_tier, 0, 1.0)
        @test sc9.roaming.border_semantics == :reestablish
        sc10 = SimConfig(1, 2, 1000, 10.0, 5.0, 5.0, :single_tier, 0, 1.0,
                         MobilityConfig())
        @test sc10.roaming.border_semantics == :reestablish
    end

    @testset "5G border crossing, re-establishment semantics (deployed default)" begin
        topology = _mini_topology()
        scale = 1000
        state = _state(topology; scale = scale)

        ctx = Simulation.create_session_context(1, topology)
        push!(state.upf_sessions_5g[1], ctx)
        agent_sessions = [ctx]
        home_anchor = ctx.metadata.anchor_upf_index

        new_sessions = Simulation.dispatch_handover!(state, topology, agent_sessions,
                                                     1, 2, 1, 2, 1, 1, 1, 2)

        # σ: the full HR PDU-session establishment transaction, NOT an intra-PLMN σ.
        @test state.sigma_roam_5g == SIGMA_ROAM_5G_REEST
        @test state.sigma_5g_xn == 0
        @test state.sigma_5g_n2 == 0

        # The flow breaks: one session per real user re-established from scratch.
        @test state.session_breaks_5g == 1 * scale

        # The charging context is rebuilt with the new session (acct relocation).
        @test state.acct_reloc_5g == 1 * scale

        # Per-session forwarding state is still (re)written at the serving UPF.
        @test state.core_writes_5g == 1 * scale

        # One border event.
        @test state.roam_entries == 1

        # HR: the anchor stays in the HOME network (H-UPF/PSA) — the pin survives
        # re-establishment; the roaming cost on the data plane is path-stretch.
        @test new_sessions[1].metadata.anchor_upf_index == home_anchor
        @test new_sessions[1].metadata.operator_id == 2
    end

    @testset "5G border crossing, idealized inter-PLMN HO (sensitivity)" begin
        topology = _mini_topology()
        scale = 1000
        state = _state(topology; scale = scale, semantics = :ideal_ho)

        ctx = Simulation.create_session_context(1, topology)
        push!(state.upf_sessions_5g[1], ctx)
        agent_sessions = [ctx]

        Simulation.dispatch_handover!(state, topology, agent_sessions,
                                      1, 2, 1, 2, 1, 1, 1, 2)

        # Best case 3GPP permits (rarely deployed): ~N2 + N32 envelope.
        @test state.sigma_roam_5g == SIGMA_ROAM_5G_IDEAL
        # Session survives: no break, no accounting relocation.
        @test state.session_breaks_5g == 0
        @test state.acct_reloc_5g == 0
        # Tunnel state still rewritten at the new serving UPF.
        @test state.core_writes_5g == 1 * scale
        @test state.roam_entries == 1
    end

    @testset "6G-RUPA border crossing: enrollment + renumber, flow survives" begin
        topology = _mini_topology()
        state = _state(topology)

        Simulation.handle_handover_6grupa!(state, topology, 1, 2, 1, 2, 1, 2)

        # Enrollment (~200) + flat renumber (200) + internetwork advert (~50).
        @test state.sigma_roam_rupa == SIGMA_ROAM_RUPA
        @test state.sigma_rupa_intra == 0
        @test state.sigma_rupa_inter == 0
        # ΔS_core = 0 and accounting untouched across the operator boundary too.
        @test state.core_writes_rupa == 0
        @test state.acct_reloc_rupa == 0
    end

    @testset "charge_roaming_entry!: arrival is establishment, not a break" begin
        topology = _mini_topology()
        scale = 1000
        state = _state(topology; scale = scale)

        Simulation.charge_roaming_entry!(state, 2)

        # Entry = the establishment transaction itself, in BOTH B7a semantics
        # (an arriving roamer has no prior session in this network).
        @test state.sigma_roam_5g == SIGMA_ROAM_5G_REEST
        @test state.sigma_roam_rupa == SIGMA_ROAM_RUPA
        @test state.roam_entries == 1
        # Nothing breaks and no accounting context relocates at entry.
        @test state.session_breaks_5g == 0
        @test state.acct_reloc_5g == 0
        # HR transit-state gauge: the roamer's sessions are held as per-roamer
        # state along the HR chain (V-UPF + IPUPS×2 + H-UPF) while active.
        @test state.roam_sessions_5g == 2 * scale
    end

    @testset "roamer injection end-to-end (mobile lifecycle)" begin
        function _run_mini_sim(roamer_fraction; n_agents = 5)
            topology = _mini_topology()
            config = SimConfig(1, 1, 1000, 3.0, 5.0, 0.001, :two_tier, 1, 1.0,
                               MobilityConfig(true, 1.0, RandomWaypoint(5.0, 0.0, 1.0)),
                               RoamingConfig(:reestablish, roamer_fraction))
            state = Simulation.init_global_state_for_simulation(topology, config)
            env = ConcurrentSim.Simulation()
            for i in 1:n_agents
                @process Simulation.user_lifecycle(env, i, state, topology, eMBB)
            end
            ConcurrentSim.run(env, config.duration)
            return state
        end

        # Every agent a roamer: every attach is a border entry.
        st1 = _run_mini_sim(1.0)
        @test st1.roam_entries == 5
        @test st1.sigma_roam_5g == 5 * SIGMA_ROAM_5G_REEST
        @test st1.sigma_roam_rupa == 5 * SIGMA_ROAM_RUPA
        @test st1.roam_sessions_5g == 5 * 1 * 1000

        # No roamers: roaming counters stay zero.
        st0 = _run_mini_sim(0.0)
        @test st0.roam_entries == 0
        @test st0.sigma_roam_5g == 0
        @test st0.sigma_roam_rupa == 0
        @test st0.roam_sessions_5g == 0
    end

    @testset "subsequent intra-visited moves are ordinary handovers" begin
        topology = _mini_topology()
        scale = 1000
        state = _state(topology; scale = scale)

        ctx = Simulation.create_session_context(1, topology)
        push!(state.upf_sessions_5g[1], ctx)

        # Border crossing into operator 2 …
        s2 = Simulation.dispatch_handover!(state, topology, [ctx],
                                           1, 2, 1, 2, 1, 1, 1, 2)
        # … then a move INSIDE the visited network (operator 2 → operator 2).
        Simulation.dispatch_handover!(state, topology, s2,
                                      2, 1, 2, 1, 2, 1, 2, 2)

        # Only the first event was a roaming event.
        @test state.roam_entries == 1
        @test state.sigma_roam_5g == SIGMA_ROAM_5G_REEST
        @test state.sigma_roam_rupa == SIGMA_ROAM_RUPA
        # The second event took the normal intra-PLMN branches.
        @test state.sigma_5g_n2 == 1150
        @test state.sigma_rupa_inter == 200
        @test state.session_breaks_5g == 1 * scale   # unchanged by second event
    end
end
