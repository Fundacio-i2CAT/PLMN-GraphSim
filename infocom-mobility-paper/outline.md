# INFOCOM Mobility Paper — Living Outline

**Working Title**: Beyond Static Aggregation: Handover and Roaming Signaling Cost of 6G-RUPA vs 5G Under Mobility

---

## Abstract
- Extend prior O(1)-forwarding-state result for 6G-RUPA to mobile case: handovers are dominant event, not just attachments.
- Generalize conditional mobility-invariance theorem to handle inter-domain handovers; derive core-state delta when domain boundary crossed.
- Build quantitative signaling-cost model σ replacing prior paper's qualitative "potentially lower" with real message counts grounded in 3GPP/RINA specs.
- Extend to roaming: terrestrial-to-terrestrial (5G HR vs RUPA internetwork layer), then terrestrial-to-satellite (NTN-TN integration) reusing same mechanism.
- Validate on Spain/USA topologies under two mobility models; show results robust to model choice and confirm signaling advantage persists under mobility.

---

## 1. Introduction
- Recap static result: 6G-RUPA O(1) forwarding state vs 5G O(N) per-session state (scalability-paper baseline).
- State open question prior paper left: does O(1) advantage survive handover and roaming signaling?
- Contributions: (1) generalized mobility theorem, (2) quantitative Xn/N2-vs-renumbering σ model, (3) roaming/satellite extension.
- Position as natural follow-up: prior paper §V-D explicitly identified mobility as next frontier; this paper delivers those results.

---

## 2. Background
- 5G UPF/PFCP/GTP-U session state, Xn/N2 handover procedures grounded in TS 38-413/29-244 (NGAP, PFCP).
- 6G-RUPA/GUPF topological addressing, network renumbering grounded in RINA Reference Model §2.5 (address as synonym; EFCP flows persist).
- Why 5G chooses Home-Routed roaming over Local Breakout: billing/accounting (S_ctx) stays at home even though traffic anchors (S_fwd) could break out locally.
- LEOPath satellite addressing model as reusable piece for NTN extension (topological address bit-packing; no dependency on LEOPath's routing engine).

---

## 3. Generalized Mobility Model (extends prior access.tex §IV)
- Restate conditional mobility-invariance (Theorem 4 from prior): ΔS_core = 0 iff handover stays inside domain B whose prefix P_B unchanged.
- Generalize: inter-domain case (B → B' ≠ B) where P_B changes; derive ΔS_core and renumbering propagation depth.
- Introduce σ (signaling cost, separate from c_f/c_p storage costs): σ_5G^Xn, σ_5G^N2, σ_RUPA, σ_roam quantified from 3GPP/RINA message procedures.
- State generalized theorem: 6G-RUPA signaling cost stays topologically bounded across domain crossings; 5G grows with anchor distance and session count.
- Extend roaming model: σ_roam^{5G,HR} (Home-Routed anchoring via N8/N9), σ_roam^{RUPA} (N+1 internetwork recursion); both keep S_ctx trackable independently.

---

## 4. System & Simulator Extensions
- Stateful mobility models (RandomWaypoint with explicit waypoint tracking; Gauss-Markov with velocity autocorrelation).
- 5G handover path: Xn (same anchor, 600B per TS 38-413 NGAP + TS 29-244 PFCP) vs N2 (anchor change, 1150B).
- 6G-RUPA handover path: intra-domain renumbering (200B EFCP rebinding + local GUPF update) vs inter-domain (400B includes prefix withdrawal/advertisement at core).
- Roaming mechanism: built terrestrial-to-terrestrial first (validates HR anchoring model), then reused unchanged for satellite/NTN (same σ_roam formula; different domain type).

---

## 5. Evaluation Setup
- Reuse Spain/USA topologies + population from prior paper (bit-for-bit reproducible).
- Mobility intensity sweep: speed (5 km/h pedestrian, 50 km/h vehicular), domain-crossing rate (clustering UPFs to force boundary crossings).
- Two roaming scenarios: MNO-to-MNO terrestrial, then terrestrial-to-satellite via topological address.
- Two mobility models tested: Random Waypoint (baseline) + Gauss-Markov (robustness check).

---

## 6. Results
- Forwarding-state evolution: flat for RUPA intra-domain (honoring O(1) invariant), bounded but non-flat for inter-domain, growing for 5G (extends static result to mobility).
- Signaling volume: σ_5G^Xn vs σ_5G^N2 vs σ_RUPA intra/inter, cumulative and per-handover, broken down by speed/topology.
- Roaming-cost comparison: σ_roam^{5G,HR} vs σ_roam^{RUPA} terrestrial-to-terrestrial; same comparison terrestrial-to-satellite (shows reusability of mechanism).
- Billing/accounting independence: show S_ctx stays as trackable in both 5G HR and RUPA roaming (no loss of granularity).
- Both mobility models produce qualitatively consistent σ distributions (robustness to model choice).

---

## 7. Discussion & Limitations
- Out of scope: trace-replay mobility, full packet-level latency/loss during renumbering (already named in prior paper as future work).
- Control-plane shim's O(N) PFCP mapping orthogonal to this paper's data-plane result.
- Assumption: single-layer intra-domain renumbering (no cascading prefix updates); satellites have stable orbital periods (no congestion-driven domain swaps).

---

## 8. Conclusion
- 6G-RUPA's O(1) forwarding advantage proven robust to mobility and roaming, not just static attachment.
- Signaling cost model σ quantifies the "potential" claimed in prior paper; real numbers ground the comparison.
- Recursive N+1 internetworking layer generalizes beyond terrestrial, enabling NTN-TN integration without architectural change.
- Future work: trace-replay, full latency/loss simulation, P4 hardware prototype (same as prior paper's future work, now informed by mobility results).

---

## Notes & Open Items
- **Spec grounding**: All σ constants derived from 3GPP TS 38-413 v17.2.0 (NGAP IE definitions, lines 41977–42147) + TS 29-244 § 7.5.1–7.5.7 (PFCP procedures). RINA Reference Model §2.5 used for renumbering procedure validation.
- **Data collection**: Empirical σ distributions from Spain/USA simulations (pending handover-trigger fix in attachment model).
- **Roaming mechanism design**: HR vs LBO tradeoff documented; RUPA internetwork layer avoids per-flow anchor but requires address-space management across layers.
