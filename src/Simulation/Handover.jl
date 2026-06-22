using Random
using MetaGraphsNext
using ..Types

"""
    handle_handover_5g!(sim_state, topology, agent_sessions, old_upf, new_upf,
                        old_domain_id, new_domain_id, old_operator_id, new_operator_id)

Handle 5G handover, classifying as Xn (same anchor) or N2 (different anchor),
and distinguishing roaming (operator change) from intra-MNO handovers.

σ values (grounded in 3GPP specs, mobility-formal-model.md §3):
  - Xn (intra-domain, same anchor): 500 bytes
  - N2 (inter-domain, different anchor): 1080 bytes
  - Roaming (Home-Routed inter-PLMN): 1180 bytes

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
    if isempty(agent_sessions) || old_upf == new_upf
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
        # 1080 bytes per formal model §3.2 (NGAP + dual PFCP session setup/teardown)
        sim_state.sigma_5g_n2 += Int64(1080)
        1080
    else
        # Xn handover: same anchor, same domain
        # 500 bytes per formal model §3.1 (NGAP + single PFCP modification)
        sim_state.sigma_5g_xn += Int64(500)
        500
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

    sim_state.handover_count += 1
    return new_sessions
end

"""
    handle_handover_6grupa!(sim_state, topology, old_gnb, new_gnb,
                            old_domain_id, new_domain_id,
                            old_operator_id, new_operator_id)

Handle 6G-RUPA handover, classifying as intra-domain renumbering or inter-domain
prefix update, and distinguishing roaming from intra-MNO handovers.

σ values (grounded in RINA reference model and access.tex §V-D, formal model §3):
  - Intra-domain renumbering: 200 bytes
  - Inter-domain renumbering: 400 bytes
  - Inter-layer roaming: 300 bytes

In 6G-RUPA, forwarding state remains topology-bounded (O(1) per domain)
regardless of handover type.
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

    # Determine σ cost and increment appropriate counter
    sigma_bytes = if is_operator_change
        # Roaming (inter-layer, N+1 internetwork layer crossing)
        # 300 bytes per formal model §3.6 (intra-visited renumbering + optional home notification)
        sim_state.sigma_roam_rupa += Int64(300)
        300
    elseif is_domain_change
        # Inter-domain renumbering (prefix change at core)
        # 400 bytes per formal model §3.4 (intra-domain renumbering + aggregate prefix withdrawal/advertisement)
        sim_state.sigma_rupa_inter += Int64(400)
        400
    else
        # Intra-domain renumbering (prefix unchanged at core)
        # 200 bytes per formal model §3.3 (EFCP rebinding + local GUPF update)
        sim_state.sigma_rupa_intra += Int64(200)
        200
    end

    sim_state.handover_count += 1
    return
end
