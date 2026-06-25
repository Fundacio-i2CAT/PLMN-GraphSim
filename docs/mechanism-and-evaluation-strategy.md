# Mechanism & Evaluation Strategy: Mobility-Driven Handover Signaling

## Handover Signaling Model (σ)

We quantify handover signaling cost σ separately from storage cost (c_f, c_p from prior work), grounded in 3GPP and RINA specifications.

### 5G Handover Costs

**Xn Handover** (same UPF anchor, intra-domain):
- Source gNB → target gNB via Xn interface (horizontal handover).
- Signaling: NGAP Bearer Context Setup (via gNB handover message) + PFCP Session Association (UPF already serving both gNBs).
- Procedure bytes (TS 38-413 v17.2.0, TS 29-244 §7.5):
  - NGAP message: ~450B (Handover Request/Command/Confirm, IEs per 38.413 §9.3.3–9.3.4)
  - PFCP update (minimal): ~150B (Association Update, Session Establishment Acknowledge)
- **σ₅G^Xn = 600B per handover**

**N2 Handover** (UPF anchor changes, inter-domain):
- Source gNB → target gNB; target served by different UPF (requires new anchor).
- Signaling: NGAP full handover (Source gNB → AMF → Target gNB) + Release old sessions + Establish new anchor at new UPF + PFCP path setup.
- Procedure bytes (TS 38-413 v17.2.0, TS 29-244 §7.5):
  - NGAP: ~450B (Handover Request, Handover Command, Handover Confirm)
  - PFCP Release (old UPF): ~150B
  - PFCP Establish (new UPF): ~350B
  - PFCP Modify (path update): ~200B
- **σ₅G^N2 = 1150B per handover**

**5G Roaming (Home-Routed)** (inter-PLMN):
- UE in visited PLMN; traffic and session anchors in home PLMN (via N8/N9 SMF-UPF coordination).
- Signaling: intra-PLMN N2 handover cost + inter-PLMN N9 coordination.
- Procedure bytes (TS 29-244 §8.2.7 – N9 interaction for roaming):
  - Intra-PLMN: 1150B (N2 cost above)
  - Inter-PLMN: ~30B (N9 session update, PDU session context)
- **σ₅G^roam^HR ≈ 1180B per handover**

### 6G-RUPA Handover Costs

**Intra-Domain Renumbering** (same GUPF, topologically local):
- Flow IPC Processes (EFCP) remain bound; only address synonym updated (RINA Reference Model §2.5).
- Signaling: EFCP rebinding handshake + local GUPF state update.
- Procedure bytes (RINA RM):
  - EFCP address rebind: ~150B (Connection Establishment with new address, per RM Fig. 8)
  - GUPF metadata update: ~50B
- **σ_RUPA^intra = 200B per handover**

**Renumbering is FLAT across levels — superseded model.** See the canonical
`mobility-formal-model.md` §3.4. The earlier "inter-domain = prefix
withdrawal/re-advertisement at the core (400B, ΔS_core=±c_p)" claim is **wrong**:
the destination domain's aggregate prefix is fixed by topology and already present,
so a moving UE just adopts an address under it — **no core prefix is added/removed
at any level (ΔS_core = 0)**. The renumber cost is the same procedure regardless of
move distance (new synonym + local routing advertisement + per-active-flow update;
only the local neighbourhood reconverges — Grasa et al. 2017 §III):
- **σ_RUPA^renumber ≈ 200B per handover, flat across L1/L2/L3.**
- The level distinction (L1 intra-edge / L2 inter-edge / L3 inter-PSA) affects
  advertisement/directory *reach*, not core state; that scope-dependent part is the
  deferred location-management open question.

**6G-RUPA Roaming** (inter-DIF via N+1 layer):
- UE flows reference topological address in local DIF.
- Internetwork (N+1) layer forwards traffic to home DIF based on address aggregation (per access.tex §IV-B).
- Signaling: intra-DIF cost + N+1 forwarding state refresh.
- Procedure bytes:
  - Intra-DIF: 200B or 400B (intra/inter-domain, context-dependent)
  - N+1 layer refresh: ~100B (scope aggregation update)
- **σ_RUPA^roam ≈ 300B per handover** (lighter than 5G HR due to topological aggregation avoiding per-flow anchoring)

## Mechanism Micro-Validation: Minimal Topology

Sanity check that each σ counter increments by its exact spec value before
running national-scale experiments. Not the headline evidence.

**Setup**: 4 gNBs, 2 UPFs, deterministic handover path.
- gNB 1,2 → UPF 1 (Xn handovers possible)
- gNB 3,4 → UPF 2 (Xn handovers possible)
- Boundary between (1,2) and (3,4) triggers N2

**Test Scenario**: Agent traverses gNB path 1→2→3→4→1 (5 handovers total: Xn, N2, Xn, N2, Xn).
- 5 sessions per gNB transition.
- Handovers counted by type (Xn vs N2), σ incremented per specification.

**Results**:
```
5G:
  Xn (same UPF):   2 × 600B = 1200B
  N2 (diff UPF):   2 × 1150B = 2300B
  Total:           3500B

6G-RUPA (flat renumber, 200B/handover at every level):
  4 handovers × 200B = 800B
  Total:           800B

Advantage: 77% (RUPA vs 5G)   [5G 3500B vs RUPA 800B]
Note: per-event advantage now grows with 5G handover severity (Xn 67%, N2 83%),
since RUPA is flat. See mobility-formal-model.md §7.
```

This validates:
1. σ model correctly increments per handover type
2. Signaling cost difference reflects architectural choice (GTP-U tunneling + anchoring vs topological ephemeral addressing)
3. Intra-domain advantage (200B vs 600B) persists under mobility

## National-Scale Empirical Results: Spain & USA

Full OpenCellID topologies, no subsampling. 1000 persistent mobile eMBB agents,
1200 s, dt = 2 s. Serving gNB re-evaluated each tick; every cell change is a
classified handover. Reproduce with `run_national.jl spain` / `run_national.jl usa`.

**Spain** (46,396 gNBs, 20 UPFs):

| Scenario | HO/user/hr | 5G total | 6G-RUPA total | advantage |
|---|---|---|---|---|
| Pedestrian 5 km/h | 5.5 | 1.11 MB | 0.37 MB | 66.7% |
| Urban 50 km/h | 44.3 | 8.90 MB | 2.97 MB | 66.7% |
| Highway 120 km/h | 83.8 | 16.86 MB | 5.62 MB | 66.6% |

**USA** (113,210 gNBs, 30 UPFs):

| Scenario | HO/user/hr | 5G total | 6G-RUPA total | advantage |
|---|---|---|---|---|
| Pedestrian 5 km/h | 1.8 | 0.37 MB | 0.12 MB | 66.6% |
| Urban 50 km/h | 16.6 | 3.33 MB | 1.11 MB | 66.7% |
| Highway 120 km/h | 37.2 | 7.46 MB | 2.49 MB | 66.7% |

**Findings**:
- Handover rate scales with speed (more cell crossings per unit time) and with
  gNB density: USA rates ~2.8× lower than Spain because Spain is ~8× denser
  (0.092 vs 0.012 gNB/km²) → smaller cells. Physically correct.
- Xn/N2 split ≈ 99/1 in both countries: with national-scale UPF regions, almost
  all handovers stay within one anchor (Xn / RUPA intra-domain); ≈1% cross a UPF
  boundary (N2 / RUPA inter-domain). Matches operational reality.
- RUPA inter-domain event count == 5G N2 event count by construction (same
  domain crossing triggers both), at 200 B (flat renumber) vs 1150 B per event.
- 6G-RUPA advantage is 66.6–66.7% across every speed, mobility model, and
  country — it is the per-event cost ratio, invariant to topology and handover
  rate. This is the mobile generalization of the static O(1) forwarding result.

**How the earlier "0 handovers" was a bug, not a deployment limit**: the first
national attempts produced no handovers because the Random Waypoint state machine
left every agent permanently paused (zero displacement) and Gauss-Markov only
diffused. After fixing the mobility models (agents now travel at their configured
speed, verified by `test_mobility_displacement.jl` and regression tests in
`test/MobilityTests.jl`), the full 46k/113k topologies generate realistic
handover volumes directly — no subsampling, synthetic grid, or trace replay
needed. gNB density was never the obstacle.

## Robustness Notes

- **Mobility model choice**: results hold under both Random Waypoint
  (pedestrian/urban) and Gauss-Markov (highway) — the ~66.7% advantage is
  identical, confirming robustness to mobility-model choice.
- **Assumption: Stationary UPF locations**: UPFs/GUPFs remain attached to same terrestrial/satellite infrastructure over simulation duration. Orbital handovers (satellite domain) occur ~400 times per hour at equator (LEOPath data); 240s sim would see ~0–2 orbital events, acceptable as edge case.
- **Independence of S_ctx and S_fwd**: Billing/context state (S_ctx) location orthogonal to forwarding state (S_fwd) location; σ model tracks data-plane signaling only, not control-plane or accounting flows.
