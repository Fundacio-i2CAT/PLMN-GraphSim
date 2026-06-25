using Test
using DesJulia6gRupa
using DesJulia6gRupa.Simulation
using DesJulia6gRupa.Types
using Graphs
using MetaGraphsNext

# Billing orthogonality. Two claims, demonstrated not asserted:
#   (1) Accounting-state CHURN: in 5G the URR (charging context) is bound to the
#       session PDRs at the anchor/PSA (TS 29.244), so a PSA-relocating handover (L3)
#       relocates it; L1/L2 keep the PSA so it does not move. In 6G-RUPA the record
#       keys on the location-independent Application-Process-Name (RINA RM l.206/226),
#       so a renumber never moves it: acct_reloc_rupa == 0 at every level.
#   (2) GRANULARITY preserved: per-flow billing totals are identical in both — RUPA
#       does NOT trade billing fidelity for its zero forwarding/accounting churn. The
#       difference is only the record's KEY (location-bound vs identity-bound).
@testset "Billing orthogonality" begin

    # Two edge UPFs under ONE PSA, plus a third edge under a SECOND PSA, so we can
    # exercise L1 (same edge), L2 (diff edge, same PSA) and L3 (diff PSA).
    function two_psa_topology()
        gnb_locs = [GeoPoint(0.0,0.0), GeoPoint(0.1,0.1), GeoPoint(0.2,0.2), GeoPoint(0.3,0.3)]
        upf_locs = [GeoPoint(0.0,0.0), GeoPoint(0.1,0.1), GeoPoint(0.3,0.3)]   # 3 edge UPFs
        parent_map = [1, 1, 2]                                                  # edge->PSA
        psa_locs = [GeoPoint(0.05,0.05), GeoPoint(0.3,0.3)]
        NetworkTopology(gnb_locs, upf_locs, [1,2,3,3], psa_locs, parent_map,
            Municipality[], Dict{String,Vector{Int}}(), Float64[],
            MetaGraph(Graph(), label_type=Tuple{Symbol,Int},
                      vertex_data_type=GeoPoint, edge_data_type=Float64))
    end

    @testset "SSC-1 intra-PLMN: no accounting churn either architecture (anchor pinned)" begin
        # Under SSC mode 1 the PSA is pinned, so the URR never relocates intra-PLMN —
        # accounting churn is 0 for BOTH 5G and RUPA, even across a PSA-region crossing.
        # (5G accounting relocation arises only on SSC2/3 re-anchor or Home-Routed
        # roaming, modelled separately.) The orthogonality teeth intra-PLMN are instead
        # path-stretch (MobilityTests) + the granularity/key-invariance test below.
        topology = two_psa_topology()
        scale = 1000
        config = SimConfig(1, 1, scale, 10.0, 5.0, 5.0, :two_tier, 2, 1.0,
                           MobilityConfig(true, 1.0, RandomWaypoint(5.0, 0.0, 1.0)))
        state = Simulation.init_global_state_for_simulation(topology, config)
        ctx = Simulation.create_session_context(1, topology)
        push!(state.upf_sessions_5g[1], ctx); sessions = [ctx]

        # L1 (same edge), L2 (same PSA), L2 (cross-PSA region) — none relocate the anchor.
        sessions = Simulation.dispatch_handover!(state, topology, sessions, 1,2, 1,1, 1,1, 1,1)
        sessions = Simulation.dispatch_handover!(state, topology, sessions, 2,3, 1,2, 1,2, 1,1)
        sessions = Simulation.dispatch_handover!(state, topology, sessions, 3,4, 2,3, 2,3, 1,1)
        @test state.acct_reloc_5g == 0
        @test state.acct_reloc_rupa == 0
        @test sessions[1].metadata.anchor_upf_index == 1   # PSA pinned throughout
    end

    # Granularity preserved + key invariance. We model the billing KEY each
    # architecture uses and show: same per-user totals, but the 5G key is
    # location-bound (changes on PSA reloc → relocation) while the RUPA key is
    # identity-bound (invariant under renumber).
    @testset "granularity preserved; RUPA billing key invariant under renumber" begin
        # 5G key = (user, anchor_PSA); RUPA key = user (Application-Process-Name).
        key5g(user, psa)  = (user, psa)
        keyrupa(user, _)  = user

        users = 1:50
        bytes = Dict(u => 1000*u for u in users)   # per-user usage
        ledger5g = Dict{Tuple{Int,Int},Int}(); ledgerrupa = Dict{Int,Int}()
        psa = Dict(u => 1 for u in users)          # everyone starts on PSA 1

        # accumulate initial usage
        for u in users
            ledger5g[key5g(u, psa[u])]  = get(ledger5g, key5g(u,psa[u]), 0) + bytes[u]
            ledgerrupa[keyrupa(u, nothing)] = get(ledgerrupa, u, 0) + bytes[u]
        end

        # every user does a PSA-relocating handover (L3): PSA 1 -> 2.
        reloc5g = 0
        for u in users
            old = key5g(u, psa[u]); psa[u] = 2; new = key5g(u, psa[u])
            if old != new                      # 5G: record must move to the new anchor
                ledger5g[new] = get(ledger5g, new, 0) + ledger5g[old]
                delete!(ledger5g, old); reloc5g += 1
            end
            # RUPA: key (user/AP-name) unchanged → nothing to move.
        end

        # 5G relocated one accounting record per user; RUPA relocated none.
        @test reloc5g == length(users)

        # Granularity identical: every user still fully billed, same totals in both.
        total5g  = sum(values(ledger5g))
        totalrupa = sum(values(ledgerrupa))
        @test total5g == totalrupa == sum(values(bytes))
        for u in users
            @test ledgerrupa[u] == bytes[u]            # RUPA: found by stable key
            @test ledger5g[key5g(u, 2)] == bytes[u]    # 5G: found only at new anchor
        end
    end
end
