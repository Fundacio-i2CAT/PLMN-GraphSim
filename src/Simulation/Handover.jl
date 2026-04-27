using Random
using MetaGraphsNext
using ..Types

"""
    handle_handover_5g!(sim_state, topology, agent_sessions, old_upf, new_upf)

Emulate the *state side-effects* of a 5G inter-UPF handover for one UE.

For the PoC we treat any cell change that maps to a different serving UPF as a
single generic handover signaling event (Phase 1 will split this into Xn vs N2
based on whether old and new gNB share the same anchor UPF
`SessionSimMetadata.anchor_upf_index`).

Concretely:
  * The UE's `SessionContext5G` objects are removed from the old serving UPF's
    session list (`sim_state.upf_sessions_5g[old_upf]`).
  * Fresh contexts (new TEIDs/FARs, recomputed anchor UPF for two-tier) are
    pushed to the new serving UPF's list.
  * `sim_state.signaling_events_5g` is incremented by one per migrated session
    (placeholder – Phase 1 will use 3GPP per-procedure message counts).

Returns the new vector of `SessionContext5G` belonging to the agent so the
caller can keep its bookkeeping in sync.
"""
function handle_handover_5g!(sim_state::SimGlobalState,
                             topology::NetworkTopology,
                             agent_sessions::Vector{SessionContext5G},
                             old_upf::Int,
                             new_upf::Int)
    if isempty(agent_sessions) || old_upf == new_upf
        return agent_sessions
    end
    # Remove the agent's session contexts from the old UPF.
    old_list = sim_state.upf_sessions_5g[old_upf]
    # Identity comparison: contexts are immutable structs, but we hold the very
    # references that were pushed at attach time, so equality on the original
    # objects is reliable here (same TEIDs/FARs).
    filter!(s -> !(s in agent_sessions), old_list)

    # Re-establish equivalent sessions on the new serving UPF.
    new_sessions = Vector{SessionContext5G}(undef, length(agent_sessions))
    for i in eachindex(agent_sessions)
        ctx = create_session_context(new_upf, topology)
        push!(sim_state.upf_sessions_5g[new_upf], ctx)
        new_sessions[i] = ctx
        sim_state.signaling_events_5g += 1
    end
    return new_sessions
end

"""
    handle_handover_6grupa!(sim_state, topology, old_gnb, new_gnb)

Emulate a 6G-RUPA mobility event (local renumbering, paper §V-D).

Because GUPF forwarding tables are addressed by *node* (gNB / Edge GUPF), not
per UE, the table size is **unchanged** by a handover. The signaling cost is
local: only the source and target gNBs and their attached Edge GUPFs need to
update / acknowledge the new topological address. For the PoC we record a
single signaling event per cell change. Phase 1 will:
  * count the per-message bytes of the renumbering exchange,
  * model EFCP rebinding (Phase 2),
  * optionally compare against an SRv6 baseline (Phase 2/3).
"""
function handle_handover_6grupa!(sim_state::SimGlobalState,
                                 topology::NetworkTopology,
                                 old_gnb::Int,
                                 new_gnb::Int)
    if old_gnb == new_gnb
        return
    end
    sim_state.signaling_events_6grupa += 1
    return
end
