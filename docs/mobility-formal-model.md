# Generalized Mobility Model: State Invariance and Signaling Cost

**Extends:** `scalability-mno-static/paper-scalability-ieee-access/access.tex`
(forwarding-state model §IV, Theorem 4 "Conditional mobility invariance", §V-D).

**Status:** Working notes for the INFOCOM mobility paper. Numbers marked
*(approx — to ground)* still need a final spec citation; everything else is
cited inline.

---

## 0. Summary — two distinct results, do not conflate them

1. **Forwarding-state churn under mobility — O(n) vs O(1) (the headline).**
   In 5G, any handover that changes the serving UPF installs/moves **per-session**
   forwarding state (TEID/FAR/PDR), scaled by the real user population
   (`scale_factor`) → O(n) churn. In 6G-RUPA, **no** handover at **any** level
   changes the core forwarding table: a moving UE is *renumbered* into the
   destination domain, whose aggregate prefix already exists in the topology, so
   ΔS_core = 0 always. This generalizes access.tex Theorem 4 (proved only for the
   intra-domain case) to all handovers.

2. **Per-handover procedure signaling σ (the mechanism).**
   5G handover signaling is **graded** by how disruptive the move is
   (Xn < N2/edge-relocation < N2/anchor-relocation), grounded in 3GPP NGAP/PFCP.
   6G-RUPA renumbering signaling is **flat** across levels (new synonym + local
   routing advertisement + per-active-flow update), grounded in the RINA reference
   model and Grasa et al. 2017.

3. **Deferred (open question).** Location-management cost beyond the handover
   procedure itself: the RINA **directory** (name→address) maintenance, which is a
   per-DIF *policy* (Grasa et al.), and its 5G counterpart (UDM/UDR + anchor
   maintenance). Deferred **symmetrically** on both architectures.

The advantage magnitude in result (1) is structural (O(n) vs O(1)); the advantage
in result (2) rests on the per-event constants and is reported with a sensitivity
analysis.

---

## 1. Node state and domain model

Notation (from access.tex):
- $\mathcal{R}$: forwarding nodes (UPFs in 5G, GUPFs in 6G-RUPA).
- $N$: active UEs (real users). The simulator represents `scale_factor` real users
  per simulated agent; 5G per-session quantities scale by `scale_factor`.
- $S_{\mathrm{fwd}}$: forwarding state. $S_{\mathrm{ctx}}$: per-session context.
  $S_{\mathrm{total}} = S_{\mathrm{fwd}} + S_{\mathrm{ctx}}$.
- $\mathcal{P}_{\mathrm{core}}$: set of prefixes in a core/aggregating node's table;
  $S_{\mathrm{core}} = c_p \cdot |\mathcal{P}_{\mathrm{core}}|$.

**Attachment domain $\mathcal{B}$**: a region (set of co-located gNBs) reachable from
the core via one aggregate prefix $P_{\mathcal{B}}$. In the two-tier deployment the
hierarchy is `gNB → Edge UPF (UL-CL) → Centralized UPF (PSA)`; the domain hierarchy
mirrors it (edge domain ⊂ regional/PSA domain).

---

## 2. Handover taxonomy (two-tier topology)

| Level | Trigger | 5G procedure | 6G-RUPA |
|---|---|---|---|
| L0 | same gNB | none | none |
| L1 | gNB→gNB, **same edge UPF** | **Xn** (RAN-local, AMF path-switch) | local renumber |
| L2 | gNB→gNB, **diff edge UPF, same PSA** | **N2, UL-CL relocation** (anchor/IP preserved) | renumber into new edge domain |
| L3 | gNB→gNB, **diff PSA** | **N2, PSA/anchor relocation** (SSC mode 2/3) | renumber into new PSA domain |

The same physical move is classified per architecture: 5G by UPF/PSA change,
6G-RUPA by which level of the topological address changes. **Crucially, the 5G
column escalates in cost and state impact; the 6G-RUPA column does not** (§3.4, §4).

---

## 3. Signaling-cost model σ

σ is the transient cost of the handover *procedure* (messages exchanged), distinct
from steady-state storage $c_f, c_p, c_c$.

### 3.1 5G L1 — Xn handover (same anchor UPF)
NGAP Handover Request/Acknowledge (gNB↔gNB, AMF path-switch) + PFCP Session
Modification (N3 tunnel update at the UPF).
- NGAP Handover Request 250 B + Acknowledge 200 B [TS 38-413 v17.2.0 IE defs].
- PFCP Session Modification Req 100 B + Resp 50 B [TS 29-244 §7.5.4].

$$\sigma_{5G}^{\mathrm{Xn}} = 600\ \text{bytes}$$

### 3.2 5G L2 — N2 handover, edge-UPF (UL-CL) relocation, same PSA
NGAP handover + PFCP Session Release at old UL-CL + Establish at new UL-CL +
Modify (path) at both; the PSA anchor (UE IP) is preserved.
- NGAP 450 B; PFCP Release 150 B; Establish 350 B; Modify ×2 200 B
  [TS 38-413 v17.2.0; TS 29-244 §7.5.2/.4/.6].

$$\sigma_{5G}^{\mathrm{N2,UL\text{-}CL}} = 1150\ \text{bytes}$$

### 3.3 5G L3 — N2 handover, PSA / anchor relocation
PDU Session Anchor relocation (SSC mode 2/3): new PSA establishment, old PSA
release, SMF/AMF coordination, and a new UE IP / additional PDU session — the
heaviest terrestrial handover [TS 23-501 §5.6.9; TS 23-502 §4.3.5].
- NGAP 450 B + new-PSA Establish 350 B + old-PSA Release 150 B + extra
  SMF/AMF session-management + N9 path setup ≈ 550 B.

$$\sigma_{5G}^{\mathrm{N2,PSA}} \approx 1500\ \text{bytes}\quad\textit{(approx — to ground in TS 23-502 §4.3.5)}$$

### 3.4 6G-RUPA — renumbering (all levels, flat)
**Mechanism (Grasa et al. 2017 §III; RINA RM lines 1408–1410):** the moving IPCP
(UE) obtains a new synonym (address) reflecting its new location and then:
1. **advertises the new address via routing** to its direct neighbours
   (link-state update within the DIF; address→PoA);
2. **issues flow-update messages** to the IPCPs at the other end of its active
   flows, which switch to the new destination address (active-flow continuity —
   *not* a global directory lookup);
3. deprecates the old address after a timeout.

Active flows are **not** torn down: an address is a *synonym* for the IPCP, and
EFCP connections are keyed on connection-endpoint/port-ids, so a change of address
does not break the flow (RINA RM line 1408; experimentally **0 packet loss** in
IRATI, Grasa et al. Figs 6–10).

**The cost does not escalate with move distance**, because the address is
location-dependent/aggregatable: *"routing to the new address and to the old one
will be the same until packets are close to the area where the IPCP is located…
routing in the neighbourhood of the renamed IPC Process will have already
converged"* (Grasa et al. §III). Only the **local neighbourhood** reconverges; the
rest of the network (and the core) is untouched at L1, L2 **and** L3.

Cost components: new synonym + local NSM update (~50 B) + link-state advertisement
to neighbours (~50 B) + per-active-flow update (~100 B for the small number of
active flows of one UE). Conservative flat value:

$$\sigma_{\mathrm{RUPA}}^{\mathrm{renumber}} \approx 200\ \text{bytes (flat across L1/L2/L3)}$$

> **Correction note.** An earlier version of these notes modelled an inter-domain
> renumber as installing/withdrawing an aggregate prefix at the core
> ($\Delta S_{\mathrm{core}}=\pm c_p$, 400 B). That is **wrong**: the destination
> domain's aggregate prefix is fixed by topology and already present; the UE merely
> adopts an address under it. No core prefix is added or removed at any level.

### 3.5 Roaming
- **5G Home-Routed** (inter-PLMN): visited UPF anchors back to the home PLMN over
  N9; per-roaming-session inter-PLMN coordination.
  $\sigma_{\mathrm{roam}}^{5G,HR} \approx 1180$ B [TS 23-501 §4.2.8.2.3; TS 29-244 §8].
- **6G-RUPA inter-layer** (N+1 internetwork DIF): the same renumber mechanism
  applied across the internetwork layer; no fixed home anchor.
  $\sigma_{\mathrm{roam}}^{\mathrm{RUPA}} \approx \sigma_{\mathrm{RUPA}}^{\mathrm{renumber}}$
  plus an N+1-layer advertisement. Flat-renumber principle holds.

---

## 4. Core forwarding-state delta $\Delta S_{\mathrm{core}}$ per handover

**6G-RUPA — ΔS_core = 0 at every level.** The core forwards by topological
aggregate prefixes $\mathcal{P}_{\mathrm{core}}$ fixed by deployment. A handover
renumbers the UE into a destination domain whose prefix already $\in
\mathcal{P}_{\mathrm{core}}$. Therefore the prefix set is invariant:
$$T(\mathcal{P}_{\mathrm{core}}) = \mathcal{P}_{\mathrm{core}} \;\Rightarrow\; \Delta S_{\mathrm{core}} = 0,$$
independent of handover level (L1/L2/L3), handover rate $\lambda$, and user count
$N$. No host route is ever injected.

**5G — ΔS_core > 0, per session.** Any UPF change (L2/L3) releases per-session
TEID/FAR/PDR at the old UPF and installs them at the new one; under churn the
anchored/aggregating node accumulates per-session state $\propto$ sessions $\times$
`scale_factor`. Even L1 (Xn) modifies per-session N3 tunnel state at the UPF.
$$\Delta S_{\mathrm{core}}^{5G} \in \mathcal{O}(N).$$

This is the headline asymmetry and the mobile generalization of the static result.

---

## 5. Generalized mobility theorem

**Theorem (Generalized mobility invariance).** In 6G-RUPA, the core forwarding-state
size is invariant with respect to handovers at **all** levels (intra-domain,
inter-edge-domain, and inter-PSA-domain), and hence with respect to the handover
rate $\lambda$ and user count $N$: $\Delta S_{\mathrm{core}} = 0$.

**Proof sketch.** Let $\mathcal{P}_{\mathrm{core}}$ be the set of aggregate prefixes
the core uses to reach attachment domains; this set is determined by the deployed
topology, not by where any UE currently is. A handover renumbers the UE into the
destination domain $\mathcal{B}'$ by assigning a new synonym under $P_{\mathcal{B}'}
\in \mathcal{P}_{\mathrm{core}}$ (RINA RM 1408–1410). Since $P_{\mathcal{B}'}$
already exists, no prefix is added or removed: $T(\mathcal{P}_{\mathrm{core}}) =
\mathcal{P}_{\mathrm{core}}$, so $\Delta S_{\mathrm{core}} = c_p \cdot
(|T(\mathcal{P}_{\mathrm{core}})| - |\mathcal{P}_{\mathrm{core}}|) = 0$. Active
flows persist because the address is a synonym and EFCP is keyed on
connection-endpoint-ids, not addresses (RINA RM 1408; 0 packet loss, Grasa et al.).
Only the local neighbourhood routing reconverges (Grasa et al. §III), so the result
holds regardless of how far the UE moves. access.tex Theorem 4 is the special case
$\mathcal{B}=\mathcal{B}'$. $\square$

**Corollary (5G contrast).** A 5G handover that changes UPF installs per-session
forwarding state at the new anchor; for $M$ concurrent migrating sessions
$\Delta S_{\mathrm{core}}^{5G} = c_f \cdot M \in \mathcal{O}(N)$.

---

## 6. Billing / context independence

Per-session billing/context $S_{\mathrm{ctx}}$ (URR/CDR) is orthogonal to where
$S_{\mathrm{fwd}}$ lives. 5G Home-Routed keeps $S_{\mathrm{ctx}}$ at the home
anchor; 6G-RUPA keeps per-layer accounting. RUPA's lower $\sigma$ and ΔS_core do not
reduce billing granularity — both can produce per-UE CDRs. (Detailed accounting
signaling is part of the deferred location-management question, §8.)

---

## 7. Summary table

| Handover | 5G σ (B) | 5G ΔS_core | RUPA σ (B) | RUPA ΔS_core |
|---|---|---|---|---|
| L1 Xn / intra-edge | 600 | per-session N3 mod | 200 | **0** |
| L2 N2 UL-CL reloc | 1150 | per-session install/move | 200 | **0** |
| L3 N2 PSA reloc | ~1500* | per-session re-anchor | 200 | **0** |
| Roaming | ~1180 (HR) | per-session anchor | ~200 | **0** |

\* approx — to ground in TS 23-502 §4.3.5.

Per-event advantage grows with severity: 67% (L1) → 83% (L2) → ~87% (L3). The
state result is structural: O(n) vs O(1), independent of σ.

---

## 8. Open question (deferred, symmetric)

**Location management beyond the handover procedure.** Keeping a moving UE
reachable for *new* flows requires updating a name→address mapping:
- **6G-RUPA:** the DIF **directory**, whose maintenance is an explicit *per-DIF
  policy* — fully-replicated / hierarchical (DNS-like) / DHT (Grasa et al. §II;
  RINA RM 1380, 1388). Active flows do **not** depend on it (they use direct
  flow-update messages, §3.4).
- **5G:** UDM/UDR registration + the anchor that keeps the old IP resolvable.

Both are deployment-specific and modelled identically here as out of scope. This is
the one place where σ could grow with scope; we parameterize it as a policy and
leave quantification to future work.

---

## 9. Simulator implications

- Classify handovers by tier using `edge_upf_parent_map` (L1/L2/L3).
- 5G: charge graded σ (600/1150/~1500) **and** per-session ΔS_core scaled by
  `scale_factor` → measure core state churn over time.
- 6G-RUPA: charge flat σ (~200) and assert ΔS_core = 0 at all levels.
- Report (a) per-event σ comparison and (b) core forwarding-state churn O(n) vs
  O(1) — the two results of §0.

---

## References

- access.tex — Eq. (state model); Theorem 4 (conditional mobility invariance, line
  ~953); §IV IPC/aggregation; §V-D mobility.
- **Grasa, Bergesio, Tarzan, Lopez, Day, Chitkushev, "Seamless network renumbering
  in RINA," 2017** — renumbering walk-through (§III), directory-as-policy (§II),
  IRATI experiments (0 packet loss, RTT impact only at extreme rates, Figs 6–10).
- RINA Reference Model — address as DIF-scoped location-dependent synonym (l.1114);
  Changing Address procedure (l.1408–1410); directory name→address / address→PoA
  (l.1380, 1388); topological name spaces (l.1468–1486).
- 3GPP TS 38-413 (NGAP), TS 29-244 (PFCP), TS 23-501/23-502 (5G system / procedures,
  PSA relocation SSC modes).
