using Random
using MetaGraphsNext
using ..Types

"""
    handover_level(topology, old_upf, new_upf) -> Int

Classify a routine handover under the realistic **SSC mode 1** baseline
(mobility-formal-model.md §2), where the PDU Session Anchor (PSA) is *pinned for the
session lifetime* regardless of which cells/edge UPFs the UE moves through
(TS 23.501 §5.6.9). So the only routine levels are:
  - L1: same edge UPF                 (5G Xn, RAN-local path switch)
  - L2: different edge UPF            (5G N2 UL-CL relocation; **PSA preserved**)

Crucially, moving into a *different PSA region* does **not** relocate the anchor in
SSC mode 1 — it is still an L2 N2 handover with the original PSA kept (at the price
of a longer anchor path; see `anchor_path_stretch`). Actual PSA relocation happens
only under SSC mode 2/3 (deliberate re-anchoring), modelled as a separate optional
scenario, not a per-crossing event.
"""
function handover_level(topology::NetworkTopology, old_upf::Int, new_upf::Int)
    return old_upf == new_upf ? 1 : 2
end

"""
    crosses_psa_region(topology, old_upf, new_upf) -> Bool

Geometric marker: did the move cross into a different PSA *region* (the parent of the
serving edge UPF changed)? Under SSC mode 1 this does **not** relocate the anchor —
it just means the pinned PSA is now farther away (anchor path-stretch grows), and it
flags where an SSC mode 2/3 deployment *would* consider re-anchoring. Not charged as
a PSA relocation in the routine model.
"""
function crosses_psa_region(topology::NetworkTopology, old_upf::Int, new_upf::Int)
    pm = topology.edge_upf_parent_map
    (isempty(pm) || old_upf == new_upf) && return false
    op = old_upf <= length(pm) ? pm[old_upf] : old_upf
    np = new_upf <= length(pm) ? pm[new_upf] : new_upf
    return op != np
end

"""
    anchor_path_stretch(topology, serving_upf, pinned_psa) -> (d_pinned, d_optimal)

The SSC mode 1 user-plane cost. With the anchor pinned, 5G traffic hairpins from the
current serving edge UPF to the **original** PSA (`d_pinned`); the topologically
optimal egress (what 6G-RUPA achieves by renumbering into the local domain) is the
**nearest** PSA (`d_optimal`). The excess `d_pinned - d_optimal ≥ 0` is the path
stretch 5G pays to avoid re-anchoring. Distances in km (haversine). Single-tier or
unknown PSA ⇒ (0, 0).
"""
function anchor_path_stretch(topology::NetworkTopology, serving_upf::Int, pinned_psa::Int)
    psas = topology.centralized_upf_locations
    (isempty(psas) || serving_upf < 1 || serving_upf > length(topology.upf_locations)) && return (0.0, 0.0)
    sloc = topology.upf_locations[serving_upf]
    d_pinned = (pinned_psa >= 1 && pinned_psa <= length(psas)) ?
               haversine_distance(sloc, psas[pinned_psa]) : 0.0
    d_optimal = minimum(haversine_distance(sloc, p) for p in psas)
    return (d_pinned, d_optimal)
end

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

    # Classify handover type (SSC mode 1 baseline: PSA pinned, only L1/L2 routine).
    is_operator_change = (old_operator_id != new_operator_id)
    level = handover_level(topology, old_upf, new_upf)

    # Determine σ cost and increment appropriate counter, by level.
    sigma_bytes = if is_operator_change
        # Roaming (Home-Routed inter-PLMN): most expensive
        # 1180 bytes per formal model §3.5 (inter-visited-PLMN coordination)
        sim_state.sigma_roam_5g += Int64(1180)
        1180
    elseif level == 2
        # L2 — N2 UL-CL relocation: serving edge UPF changes, **PSA/IP preserved**
        # (SSC mode 1, TS 23.501 §5.6.9). Even a move into a different PSA region is
        # this case — the anchor stays put (longer path), it is not re-anchored.
        # 1150 bytes per formal model §3.2 (NGAP 450B + PFCP Release/Establish/Mod 700B)
        # Grounded in TS 38-413 v17.2.0 + TS 29-244 § 7.5.2/7.5.4/7.5.6 (PFCP Session procedures)
        sim_state.sigma_5g_n2 += Int64(1150)
        1150
    else
        # L1 — Xn handover: same edge UPF, RAN-local path switch.
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
        # SSC mode 1: the PSA anchor is PINNED for the session lifetime — it does NOT
        # change when the serving edge UPF changes (TS 23.501 §5.6.9). Only the
        # serving UPF (new_upf) and domain update; the anchor stays as established.
        pinned_anchor = ctx.metadata.anchor_upf_index
        new_metadata = SessionSimMetadata(new_upf, pinned_anchor, new_domain_id, new_operator_id)
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
    # (TEID/FAR/PDR) is (re)written at the serving UPF for this handover (L1 N3
    # tunnel update / L2 UL-CL re-establish), scaled by the real user population.
    # This is O(n) — the 5G side of the headline result, and it holds at SSC mode 1
    # because the *serving* UPF still changes even though the anchor is pinned.
    sim_state.core_writes_5g += Int64(length(agent_sessions)) * Int64(sim_state.config.scale_factor)

    # Accounting-state churn is 0 for routine intra-PLMN handovers in SSC mode 1: the
    # URR is bound to the session PDRs at the *pinned* anchor (TS 29.244), which does
    # not move (acct_reloc charged only on SSC mode 2/3 re-anchor or roaming, modelled
    # separately). The intra-PLMN cost of pinning is path-stretch, not accounting churn.

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

    # Accounting-state churn = 0 at every level: the charging record keys on the
    # location-independent Application-Process-Name (RINA RM l.206/226), handled by a
    # separate management task — a renumber changes the address synonym, not the
    # billing key, so the accounting context never relocates. Billing is ORTHOGONAL
    # to forwarding; per-flow granularity is unchanged (see AccountingTests).
    sim_state.acct_reloc_rupa += Int64(0)

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

    # Count the physical event once, by routine SSC-1 level (L1 Xn / L2 N2). A move
    # into a different PSA region is still L2 (anchor pinned); we track those crossings
    # separately in ho_l3 as a geometric marker for path-stretch / SSC-2/3 analysis.
    level = handover_level(topology, old_upf, new_upf)
    if level == 1
        sim_state.ho_l1 += 1
    else
        sim_state.ho_l2 += 1
        crosses_psa_region(topology, old_upf, new_upf) && (sim_state.ho_l3 += 1)
    end

    # Anchor path-stretch sample: with the anchor pinned (5G SSC-1) traffic hairpins
    # from the new serving edge UPF to the original PSA; RUPA egresses at the nearest
    # PSA. Use the (preserved) anchor from the agent's session metadata as the pin.
    if !isempty(agent_sessions)
        pinned_psa = agent_sessions[1].metadata.anchor_upf_index
        d5, dopt = anchor_path_stretch(topology, new_upf, pinned_psa)
        if d5 > 0.0 || dopt > 0.0
            sim_state.anchor_dist_5g_sum  += d5
            sim_state.anchor_dist_opt_sum += dopt
            sim_state.anchor_stretch_samples += 1
        end
    end

    return new_sessions
end
