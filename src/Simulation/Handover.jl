using Random
using MetaGraphsNext
using ..Types

"""
    handle_handover_5g!(sim_state, topology, agent_sessions, old_upf, new_upf,
                        old_domain_id, new_domain_id, old_operator_id, new_operator_id)

Handle 5G handover, classifying as Xn (same anchor) or N2 (different anchor),
and distinguishing roaming (operator change) from intra-MNO handovers.

σ values (grounded in 3GPP specs TS 38-413/29-244, mobility-formal-model.md §3):
  - Xn (intra-domain, same anchor): 600 bytes (refined; NGAP 450B + PFCP 150B)
  - N2 (inter-domain, different anchor): 1150 bytes (refined; NGAP 450B + Release/Establish/Mod 700B)
  - Roaming (Home-Routed inter-PLMN): 1180 bytes (5G inter-PLMN N9/N8 signaling via V-SMF)

Returns the new vector of SessionContext5G with updated metadata.
"""
function handle_handover_5g!(sim_state::SimGlobalState,
                             topology::NetworkTopology,
                             agent_sessions::Vector{SessionContext5G},
                             old_upf::Int,
                             new_upf::Int,
                             old_domain_id::Int,
                             new_domain_id::Int,
                             old_operator_id::Int,
                             new_operator_id::Int)
    if isempty(agent_sessions)
        return agent_sessions
    end

    # Classify handover type
    is_anchor_change = (old_upf != new_upf)
    is_operator_change = (old_operator_id != new_operator_id)
    is_domain_change = (old_domain_id != new_domain_id)

    # Determine σ cost and increment appropriate counter
    sigma_bytes = if is_operator_change
        # Roaming (Home-Routed inter-PLMN): most expensive
        # 1180 bytes per formal model §3.5 (inter-visited-PLMN coordination)
        sim_state.sigma_roam_5g += Int64(1180)
        1180
    elseif is_anchor_change || is_domain_change
        # N2 handover: anchor/domain UPF changes
        # 1150 bytes per formal model §3.2 (NGAP 450B + PFCP Release/Establish/Mod 700B)
        # Grounded in TS 38-413 v17.2.0 + TS 29-244 § 7.5.2/7.5.4/7.5.6 (PFCP Session procedures)
        sim_state.sigma_5g_n2 += Int64(1150)
        1150
    else
        # Xn handover: same anchor, same domain
        # 600 bytes per formal model §3.1 (NGAP 450B + PFCP Session Mod 150B)
        # Grounded in TS 38-413 v17.2.0 (NGAP IE definitions) + TS 29-244 § 7.5.4 (PFCP)
        sim_state.sigma_5g_xn += Int64(600)
        600
    end

    # Remove the agent's sessions from old UPF
    old_list = sim_state.upf_sessions_5g[old_upf]
    filter!(s -> !(s in agent_sessions), old_list)

    # Re-establish sessions at new UPF with updated metadata
    new_sessions = Vector{SessionContext5G}(undef, length(agent_sessions))
    for i in eachindex(agent_sessions)
        ctx = agent_sessions[i]
        # Create new session context at the new UPF, preserving or updating metadata as needed
        new_anchor = is_anchor_change ? new_upf : ctx.metadata.anchor_upf_index
        new_metadata = SessionSimMetadata(new_upf, new_anchor, new_domain_id, new_operator_id)
        new_forwarding = ForwardingState5G(
            rand(UInt32), rand(UInt32),  # New TEIDs
            ctx.forwarding.ul_far,
            ctx.forwarding.dl_far
        )
        new_ctx = SessionContext5G(new_forwarding, new_metadata)
        push!(sim_state.upf_sessions_5g[new_upf], new_ctx)
        new_sessions[i] = new_ctx
    end

    # Core forwarding-state churn: every session's per-session tunnel state
    # (TEID/FAR/PDR) must be (re)written at the UPF for this handover, scaled by
    # the real user population. This is O(n) — the 5G side of the headline result.
    sim_state.core_writes_5g += Int64(length(agent_sessions)) * Int64(sim_state.config.scale_factor)

    return new_sessions
end

"""
    handle_handover_6grupa!(sim_state, topology, old_gnb, new_gnb,
                            old_domain_id, new_domain_id,
                            old_operator_id, new_operator_id)

Handle 6G-RUPA handover, classifying as intra-domain renumbering or inter-domain
prefix update, and distinguishing roaming from intra-MNO handovers.

σ values (grounded in RINA RM l.1408-1410, Grasa et al. 2017 §III, formal model §3.4):
  - Renumbering: FLAT 200 bytes at every level (intra- and inter-domain alike).
    The destination domain's aggregate prefix already exists in the topology, so
    the UE just adopts an address under it — same procedure regardless of move
    distance. intra/inter are kept only as EVENT CLASSIFIERS, charged equally.
  - Inter-layer roaming: 300 bytes (flat renumber + N+1 advertisement).

In 6G-RUPA, core forwarding state is invariant to handovers at EVERY level
(ΔS_core = 0); only the local neighbourhood routing reconverges.
"""
function handle_handover_6grupa!(sim_state::SimGlobalState,
                                 topology::NetworkTopology,
                                 old_gnb::Int,
                                 new_gnb::Int,
                                 old_domain_id::Int,
                                 new_domain_id::Int,
                                 old_operator_id::Int,
                                 new_operator_id::Int)
    if old_gnb == new_gnb
        return
    end

    # Classify handover type
    is_operator_change = (old_operator_id != new_operator_id)
    is_domain_change = (old_domain_id != new_domain_id)

    # Renumbering cost is FLAT across levels (mobility-formal-model.md §3.4): a
    # moving UE adopts an address under the destination domain's pre-existing
    # aggregate prefix — same procedure (new synonym + local routing advertisement
    # + per-active-flow update) regardless of move distance, and ΔS_core = 0 at
    # every level. We still CLASSIFY intra vs inter (event classifier feeding the
    # 5G-N2 / state-churn comparison), but charge the same flat 200 B.
    # Grounded in RINA RM l.1408-1410 and Grasa et al. 2017 §III.
    const_RENUMBER = Int64(200)
    sigma_bytes = if is_operator_change
        # Inter-layer roaming (N+1 internetwork DIF): flat renumber + small N+1
        # advertisement. Kept slightly higher to reflect the extra layer hop.
        sim_state.sigma_roam_rupa += Int64(300)
        300
    elseif is_domain_change
        # Cross-domain renumber: classified as inter, charged flat renumber.
        sim_state.sigma_rupa_inter += const_RENUMBER
        const_RENUMBER
    else
        # Intra-domain renumber.
        sim_state.sigma_rupa_intra += const_RENUMBER
        const_RENUMBER
    end

    # Core forwarding-state churn = 0 at every level: the UE renumbers into a
    # destination domain whose aggregate prefix already exists in the topology, so
    # no per-session host route is written at the core (ΔS_core = 0). Only the
    # local neighbourhood routing reconverges. This is the O(1) side of the result.
    sim_state.core_writes_rupa += Int64(0)

    return
end

"""
    dispatch_handover!(sim_state, topology, agent_sessions,
                       old_gnb, new_gnb, old_upf, new_upf,
                       old_domain_id, new_domain_id, old_operator_id, new_operator_id)

Single entry point for a physical handover (one serving-gNB change). Drives both
the 5G and 6G-RUPA state machines with the SAME pre-handover old/new context, and
counts the physical event exactly once.

This wraps the two `handle_handover_*!` functions so callers cannot (a) mutate the
old domain/UPF before the 6G-RUPA classification runs, or (b) double-count the
event by incrementing `handover_count` in each handler — both were latent bugs
when the dispatch was inlined per-call. Returns the updated 5G session vector.
"""
function dispatch_handover!(sim_state::SimGlobalState,
                            topology::NetworkTopology,
                            agent_sessions::Vector{SessionContext5G},
                            old_gnb::Int, new_gnb::Int,
                            old_upf::Int, new_upf::Int,
                            old_domain_id::Int, new_domain_id::Int,
                            old_operator_id::Int, new_operator_id::Int)
    new_sessions = handle_handover_5g!(sim_state, topology, agent_sessions,
                                       old_upf, new_upf,
                                       old_domain_id, new_domain_id,
                                       old_operator_id, new_operator_id)
    handle_handover_6grupa!(sim_state, topology, old_gnb, new_gnb,
                            old_domain_id, new_domain_id,
                            old_operator_id, new_operator_id)
    sim_state.handover_count += 1
    return new_sessions
end
