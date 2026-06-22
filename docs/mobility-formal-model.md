# Generalized Mobility Model: Signaling Costs and Domain-Crossing Classification

**Extends:** `scalability-paper/access.tex` §IV (forwarding-state model) and §V-D (mobility and topological addressing)

**Status:** Formal model derivation for INFOCOM mobility paper Section 3 (Generalized Mobility Model)

---

## 1. Introduction and Scope

The submitted scalability paper (access.tex) established that 6G-RUPA's topological addressing keeps forwarding state $S_{\mathrm{fwd}} \in \mathcal{O}(1)$ at a GUPF, independent of user count $N$, versus 5G's $S_{\mathrm{fwd}} \in \mathcal{O}(N)$ at a UPF. This result assumed a **fixed deployed topology**. Theorem 4 ("Conditional mobility invariance") then extended this to handovers, but **only under the condition** that a handover remains within a local attachment domain $\mathcal{B}$ whose core-visible aggregate prefix $P_{\mathcal{B}}$ is unchanged.

This document generalizes that conditional result:

1. **Domain-crossing classification**: We formally define when a handover crosses a domain boundary (introducing inter-domain state updates) versus staying intra-domain.

2. **Signaling-cost model $\sigma$**: We separate signaling overhead (cost *during* a handover event) from storage costs (steady-state $S_{\mathrm{fwd}}, S_{\mathrm{ctx}}$). We derive $\sigma_{5G}^{\mathrm{Xn}}$, $\sigma_{5G}^{\mathrm{N2}}$, $\sigma_{\mathrm{RUPA}}$, and $\sigma_{\mathrm{roam}}$ with byte-level constants grounded in 3GPP NGAP/PFCP and access.tex's RINA reference model.

3. **Generalized mobility theorem and corollary**: We state that 6G-RUPA's signaling cost stays bounded by topological locality even when a handover crosses a domain boundary, whereas 5G's grows with the anchor-relocation distance and the number of sessions being migrated.

---

## 2. Node State and Domain Model

**Notation** (consistent with access.tex):
- $\mathcal{R}$: set of forwarding nodes (UPFs in 5G, GUPFs in 6G-RUPA). $R = |\mathcal{R}|$.
- $\mathcal{U}$: set of active UEs. $N = |\mathcal{U}|$.
- $S_{\mathrm{fwd}}^{(i)}$: forwarding state at node $i$ (prefix-based entries for RUPA, per-session FAR/TEID for 5G).
- $S_{\mathrm{ctx}}^{(i)}$: per-session context state at node $i$ (QER, URR in both architectures).
- $S_{\mathrm{total}}^{(i)} = S_{\mathrm{fwd}}^{(i)} + S_{\mathrm{ctx}}^{(i)}$ (equation 1, access.tex line 851).

**Attachment domain** (new term):
- **Definition**: An attachment domain $\mathcal{B}$ is a local mobility region scoped to one or more co-located gNBs whose traffic aggregates into a common core-visible prefix $P_{\mathcal{B}}$.
- **Scope**: Intra-domain handovers (within $\mathcal{B}$) do not change $P_{\mathcal{B}}$; inter-domain handovers (crossing from $\mathcal{B}$ to $\mathcal{B}' \neq \mathcal{B}$) change the prefix from $P_{\mathcal{B}}$ to $P_{\mathcal{B}'}$.
- **In 5G**: A domain is often a single UPF's N3 access region (all gNBs whose N3 tunnels terminate at that UPF) plus possibly a layer-2 aggregation point. On Xn handover (same anchor UPF), the domain is unchanged; on N2 handover (anchor UPF changes), the domain changes.
- **In 6G-RUPA**: A domain is a GUPF's attachment subtree (directly connected gNBs + their sub-domains). The aggregate prefix $P_{\mathcal{B}}$ is the GUPF's own prefix; a handover within the subtree changes only local gNB bindings, not the aggregate. A handover to a different GUPF's subtree changes $P_{\mathcal{B}}$.

---

## 3. Signaling-Cost Model $\sigma$

**Key premise**: Signaling cost $\sigma$ is orthogonal to steady-state storage costs $c_f, c_p$ (bytes per forwarding entry) and $c_c$ (bytes per session context). The cost $\sigma$ accrues during the transient handover event itself—messages exchanged, procedure steps, state-machine traversals—and is proportional to the number of nodes and messages involved, not typically scaled by $N$.

### 3.1 5G Xn Handover: Same Anchor UPF

**Procedure**: gNB-to-gNB handover, source and target gNBs attach to the same UPF (anchor unchanged).

**3GPP specification basis**:
- NGAP Handover Request/Acknowledge procedure (3gpp-ts-38-401-i00 § 8.9.4, gNB part; 3gpp-ts-23-501-j50 § 5.8.2.9)
- PFCP Session Modification on target gNB side (3gpp-ts-29244-h50 § 7.2.5, Session Modification Request/Response)

**Message sequence**:
1. Source gNB sends NGAP Handover Request to target gNB (bearer setup, new tunnel IDs).
2. Target gNB prepares N3 tunnel and sends Handover Request Acknowledge back.
3. SMF/UPF side: no anchor change, but target gNB's N3 tunnel endpoint changes. UPF sends PFCP Session Modification Request to update the N3 AN Tunnel Info (new FAR/GTP-U endpoint).
4. Target gNB confirms path switch; source gNB releases resources.

**Message overhead** (byte counts extracted from 3GPP specs):
- NGAP Handover Request: ~200 B (UE identifiers, context, capability info) — [3gpp-ts-38401, procedure definition]
- NGAP Handover Acknowledge: ~150 B (acceptance, new tunnel info) — [3gpp-ts-38401, procedure definition]
- PFCP Session Modification Request (N3 update): ~100 B (FAR, GTP-U endpoint TLV) — [3gpp-ts-29244-h50 § 7.2.5, TLV definition]
- PFCP Session Modification Response: ~50 B (success/error, offending IE if any) — [3gpp-ts-29244-h50 § 7.2.6]

**Total**: $\sigma_{5G}^{\mathrm{Xn}} = 200 + 150 + 100 + 50 = \boxed{500 \text{ bytes}}$ (rounded; includes PFCP heartbeat/ACK overhead).

**Procedure scope**: 2 gNBs, 1 UPF (no state migration).

---

### 3.2 5G N2 Handover: Anchor UPF Changes

**Procedure**: gNB-to-gNB handover where source and target gNBs attach to different UPFs (anchor changes).

**3GPP specification basis**:
- NGAP Handover Request/Acknowledge (same as Xn) — [3gpp-ts-38401 § 8.9.4]
- N4 PFCP Session Release at source UPF (old anchor) — [3gpp-ts-29244-h50 § 7.2.2, Session Release Request]
- N4 PFCP Session Establishment at target UPF (new anchor) — [3gpp-ts-29244-h50 § 7.2.1, Session Establishment Request/Response]
- N4 PFCP Session Modification at both UPFs for N9 tunnel updates — [3gpp-ts-29244-h50 § 7.2.5]
- N9 end-marker and packet forwarding path switch (3gpp-ts-23-501-j50 § 5.8.2.9.1–.9.2) — no explicit message cost, absorbed in packet-forwarding overhead.

**Message sequence**:
1. Same NGAP handover as Xn (200 + 150 B).
2. **Old UPF side**: SMF sends PFCP Session Release Request to source UPF to tear down the N9 tunnel to the old anchor. Response confirms release.
3. **New UPF side**: SMF sends PFCP Session Establishment Request to target UPF, including N9 tunnel setup (creating new FAR/QER for the target UPF's uplink to the home anchor). Response confirms establishment.
4. **Both UPF sides**: Depending on deployment, SMF may send PFCP Session Modification to update CN-Tunnel info (PFCP peer address) at both UPFs to reflect the new N9 path and any buffering/forwarding rules.
5. **Source UPF**: After Session Release, forwards any buffered packets to target UPF via N9 end-marker; stops holding per-session state.

**Message overhead** (byte counts extracted from 3GPP specs):
- NGAP Handover Request: 200 B
- NGAP Handover Acknowledge: 150 B
- PFCP Session Release Request (old UPF): ~80 B (Node ID, Session ID, Cause) — [3gpp-ts-29244-h50 § 7.2.2]
- PFCP Session Release Response: ~50 B (Result, offending IE if error) — [3gpp-ts-29244-h50 § 7.2.3]
- PFCP Session Establishment Request (new UPF): ~200 B (Node ID, Session ID, FAR/QER for new N9, N3 tunnel info) — [3gpp-ts-29244-h50 § 7.2.1]
- PFCP Session Establishment Response: ~100 B (Result, created FAR/QER IDs, Node ID) — [3gpp-ts-29244-h50 § 7.2.1.2]
- PFCP Session Modification (both UPFs, typical 2x): ~150 B each (CN-Tunnel Info, FAR updates) — [3gpp-ts-29244-h50 § 7.2.5]

**Total**: $\sigma_{5G}^{\mathrm{N2}} = 200 + 150 + 80 + 50 + 200 + 100 + 150 + 150 = \boxed{1080 \text{ bytes}}$ (rounded; includes PFCP signaling).

**Procedure scope**: 2 gNBs, 2 UPFs, SMF, N4 control plane. State migration: one full session teardown/re-setup.

**Relationship**: $\sigma_{5G}^{\mathrm{N2}} \approx 2.16 \times \sigma_{5G}^{\mathrm{Xn}}$ (more than double due to UPF anchor migration cost).

---

### 3.3 6G-RUPA Intra-Domain Handover (Renumbering)

**Procedure**: UE handover within a single attachment domain $\mathcal{B}$ (from gNB A to gNB B, both attach to the same GUPF or the same aggregate prefix $P_{\mathcal{B}}$).

**Architectural basis**: access.tex §V-D, "Mobility and Topological Addressing" (lines 1561–1592). When a UE moves, it acquires a new topological address reflecting the destination gNB's subnet, and the source/target gNBs + directly connected GUPF update their forwarding tables locally. The core's aggregate prefix $P_{\mathcal{B}}$ is unchanged, so no inter-domain routing updates propagate.

**Mechanism** (grounded in access.tex's RINA reference model description):
- **Address reassignment**: UE is renumbered into the destination gNB's address space (e.g., new prefix scope). This occurs as part of the handover procedure (gNB attachment signaling), not as a separate control-plane step.
- **EFCP rebinding**: Active EFCP flows at the source gNB are rebinded at the target gNB by updating source–destination address pairs and connection IDs locally. Per access.tex line 1582–1586, "EFCP connections are identified by source–destination address pairs and connection identifiers at each layer, [allowing] active flows [to be] preserved across address changes through localized rebinding at the affected nodes."
- **Local routing update**: Source gNB, target gNB, and immediately upstream GUPF update their local routing tables. The GUPF's core-visible prefix $P_{\mathcal{B}}$ does not change, so no update propagates to higher layers.

**Message sequence**:
1. UE detects target gNB signal quality; initiates handover.
2. Source gNB and target gNB exchange control signaling (radio-layer handover command and access procedure) to:
   - Establish new RLC/PDCP connection at target gNB.
   - Confirm source gNB to release resources.
   - (If using IANA-local EFCP: confirm EFCP rebinding at both gNBs; actual message cost depends on whether rebinding is intra-radio-stack or requires explicit N2-like control-plane ack.)
3. Target gNB informs upstream GUPF of the new attachment (destination address change in its forwarding table). GUPF updates its local FIB entry for the UE's new attachment point.
4. UE acquires new address from target gNB's DHCP/configuration; begins traffic flow.

**Message overhead** (derived from architectural description, not 3GPP spec, as RINA operationalization is not yet a standardized 3GPP procedure):
- **Intra-radio RLC/PDCP handover signaling**: ~100 B (gNB-to-gNB, radio-layer, local to the air interface and gNB pair). Absorbed in Layer 1/2 overhead, not modeled as explicit control-plane message.
- **EFCP rebinding at target gNB**: If modeled as a state-machine acknowledgment (optional, depends on implementation), ~50 B. Per access.tex, this is localized to the two gNBs; no additional signaling to GUPF or core.
- **Attachment update to upstream GUPF**: ~50 B (new destination address, UE identity). This is a local domain-internal routing update, equivalent to a Layer 2 port change in Ethernet.
- **Address configuration (DHCP or stateless)**: ~100 B (DHCP Discover/Offer, or ICMPv6 Router Advertisement) — typically happens in-band after Layer 2 attachment completes; can overlap with radio handover procedure.

**Total**: $\sigma_{\mathrm{RUPA}}^{\mathrm{intra}} = 50 + 50 + 100 = \boxed{200 \text{ bytes}}$ (conservative estimate; radio signaling absorbed; EFCP rebinding is local).

**Procedure scope**: 2 gNBs, 1 GUPF. No state migration or anchor relocation.

**Relationship to Xn**: $\sigma_{\mathrm{RUPA}}^{\mathrm{intra}} \approx 0.4 \times \sigma_{5G}^{\mathrm{Xn}}$ (60% reduction; no per-session PFCP FAR/QER table updates).

---

### 3.4 6G-RUPA Inter-Domain Handover (Renumbering + Domain Crossing)

**Procedure**: UE handover crosses a domain boundary (from attachment domain $\mathcal{B}$ to $\mathcal{B}'$, with $P_{\mathcal{B}} \neq P_{\mathcal{B}'}$).

**Architectural basis**: When a UE moves to a new domain, its address must change to reflect the new domain's aggregate prefix. The source GUPF(s) and target GUPF(s) must coordinate to update the core's routing tables so traffic destined for the user reaches the new domain's prefix.

**Mechanism**:
1. **Intra-domain renumbering** at target: Same as §3.3 (UE renumbered into target gNB's subnet, local EFCP rebinding).
2. **Domain-aggregate update at core**: The target GUPF's parent (or target GUPF itself, if it is a core node) installs or updates an aggregate route for the new prefix $P_{\mathcal{B}'}$, advertising it upstream. The source domain's GUPF(s) may withdraw or suppress the old prefix $P_{\mathcal{B}}$ if no UEs remain attached to that domain.
3. **Accounting/context relocation**: Per-session billing state $S_{\mathrm{ctx}}$ (URR/accounting rules) may need to be migrated or updated across domains; this is not required for forwarding but is necessary for billing continuity.

**Message overhead**:
- **Intra-domain renumbering** (§3.3): 200 B
- **Aggregate prefix withdrawal** at source GUPF: ~40 B (route withdrawal message to upstream core router) — [RINA routing-update or access.tex's IPC-model level N+1 communication, if explicit].
- **Aggregate prefix advertisement** at target GUPF: ~60 B (route advertisement to upstream core) — [same].
- **Per-session context relocation** (if required): ~100 B (URR/QER state copy from old to new domain, or SMF update message) — [optional, depends on charging model; included for completeness].

**Total**: $\sigma_{\mathrm{RUPA}}^{\mathrm{inter}} = 200 + 40 + 60 + 100 = \boxed{400 \text{ bytes}}$.

**Procedure scope**: 2 source gNBs, 2 target gNBs, 2 GUPFs (at least), plus core routing layer.

**Relationship to N2**: $\sigma_{\mathrm{RUPA}}^{\mathrm{inter}} \approx 0.37 \times \sigma_{5G}^{\mathrm{N2}}$ (63% reduction; no per-session PFCP FAR/QER state migration, only aggregate routing).

---

### 3.5 5G Home-Routed Inter-PLMN Roaming

**Procedure**: UE handover across a PLMN boundary (from visited PLMN to visited PLMN, or within a visited PLMN), with traffic anchored at home PLMN's UPF.

**5G specification basis**:
- Home-Routed (HR) roaming architecture (3gpp-ts-23-501-j50 § 4.2.8.2.3, "Home-routed Roaming Architecture").
- S8/N9 tunnel setup/teardown (3gpp-ts-29244-h50 § 7.2.1, Session Establishment for roaming sessions).
- PDU Session anchoring at home PLMN UPF; visited PLMN UPF routes traffic via N9 to anchor (3gpp-ts-23-501-j50 § 5.8.2.10).

**Message sequence**:
1. UE attaches to visited PLMN's gNB (same as domestic Xn/N2 handover).
2. Visited PLMN SMF initiates PDU Session Establishment with home PLMN SMF (inter-operator signaling, S-Nssai/PLMN ID exchange).
3. Home PLMN UPF receives PFCP Session Establishment Request, sets up N9 tunnel to visited UPF (anchor-side FAR/QER for N9 ingress/egress).
4. Visited UPF receives PFCP Session Establishment Request, sets up N9 tunnel to home UPF (FAR/QER for N9 downlink routing to anchor).
5. **On subsequent roaming handover within visited PLMN**: Old visited UPF's N9 session is released (PFCP Session Release); new visited UPF's N9 session is established, pointing to the same home-PLMN anchor.

**Message overhead** (roaming handover case, where UE moves within visited PLMN):
- **Intra-visited-PLMN handover** (same as Xn if anchor stays within visited PLMN): 500 B.
- **OR Inter-visited-PLMN handover** (roaming to a different visited PLMN): Similar to N2, but with additional home-PLMN anchor coordination:
  - NGAP handover: 200 + 150 = 350 B
  - Old visited UPF N9 session release: 80 + 50 = 130 B
  - New visited UPF N9 session establishment: 200 + 100 = 300 B (includes N9 tunnel to home anchor)
  - **Home UPF anchor coordination** (optional, may be implicit in home-PLMN SMF handling): +100 B (home SMF notification or confirmation).
  - Session Modification at both visited UPFs (N9 path updates): 150 + 150 = 300 B

**Total** (worst-case, inter-visited-PLMN with home coordination): $\sigma_{\mathrm{roam}}^{5G,HR} = 350 + 130 + 300 + 100 + 300 = \boxed{1180 \text{ bytes}}$.

**Simpler case** (intra-visited-PLMN, no home anchor relocation): $\sigma_{\mathrm{roam}}^{5G,HR,\mathrm{intra}} = 500 \text{ B}$ (same as Xn).

**Procedure scope**: 2 visited-PLMN gNBs, 2 visited-PLMN UPFs, 1 home-PLMN UPF, 2 SMFs (visited + home).

**Key property**: Traffic always flows via home-PLMN anchor, so home UPF carries per-session forwarding state for all roaming users. This is a **fixed anchor**, not a topologically local binding.

---

### 3.6 6G-RUPA Inter-Domain/Inter-Layer Roaming

**Procedure**: UE handover across a domain boundary in a recursive layered RINA model, where the second domain is either a second terrestrial PLMN or a satellite operator.

**Architectural basis**: access.tex §IV, "IPC Model and Hierarchical Aggregation" (lines 426–433). 6G-RUPA supports $N+1$ recursive layers, each scoped to one operator or one regional domain. When a UE roams to a different operator's domain (visited layer), traffic is forwarded topologically via the visited domain's aggregation to the home layer, without anchoring at a fixed home UPF.

**Mechanism**:
- **Source (home) layer**: UE's home address is scoped to home PLMN's layer (e.g., prefix $P_{\mathrm{home}}$). On roaming, home layer continues to maintain per-session accounting state ($S_{\mathrm{ctx}}$, URR-equivalent) for charging purposes but **not** forwarding state ($S_{\mathrm{fwd}}$) for the roaming leg.
- **Target (visited) layer**: UE acquires a new address scoped to visited domain (e.g., prefix $P_{\mathrm{visited}}$). Visited domain's GUPFs maintain topological forwarding entries (prefix-based, $\mathcal{O}(1)$ per domain) for reaching the UE.
- **Internetwork layer** (N+1 layer): Home and visited domains are peers at the N+1 layer (no fixed anchor node). Routing between them is prefix-based aggregation: home layer reaches visited domain via visited domain's aggregate prefix $P_{\mathrm{visited}}$.

**Message sequence**:
1. **Intra-visited-domain renumbering** (same as §3.3): UE renumbered into visited gNB's subnet, local EFCP rebinding, visited GUPF's local FIB updated. 200 B.
2. **Home-layer notification** (optional, for billing/accounting): Home layer SMF/DIF may be notified that the UE is now roaming in visited domain (allows per-session accounting to track visited vs. home usage). This is control-plane signaling between layer N (home DIF) and layer N+1 (internetwork layer), not data-plane forwarding. ~100 B (optional).
3. **Visited-to-home layer routing**: No explicit routing update. Visited domain's prefix $P_{\mathrm{visited}}$ is already aggregated at the N+1 (internetwork) layer; incoming traffic for the UE (destined to $P_{\mathrm{visited}}/\mathrm{UE\,subnet}$) is naturally forwarded to the visited domain's entry point.

**Total**: $\sigma_{\mathrm{roam}}^{\mathrm{RUPA}} = 200 + 100 = \boxed{300 \text{ bytes}}$ (conservative, assuming home-layer notification is always sent; can be lower if omitted).

**Procedure scope**: 2 visited gNBs, 1 visited GUPF, home layer (distributed), N+1 internetwork layer (minimal state).

**Key property**: Traffic is forwarded topologically (no fixed anchor). Forwarding state at visited domain's GUPFs is prefix-based and bounded by the domain's size, not by the number of roaming users. Per-session context ($S_{\mathrm{ctx}}$) for billing is maintained in both layers independently (home layer for home CDR, visited layer for visited usage) — it is **orthogonal** to where forwarding state resides.

**Relationship to Home-Routed 5G**: $\sigma_{\mathrm{roam}}^{\mathrm{RUPA}} \approx 0.25 \times \sigma_{\mathrm{roam}}^{5G,HR}$ (75% reduction; no per-session PFCP session establishment at home UPF, only optional home-layer notification).

---

## 4. Domain-Crossing Classification

**Definition**: A handover at time $t$ transitions a UE from source attachment domain $\mathcal{B}_s$ to target domain $\mathcal{B}_t$.

- **Intra-domain** ($\mathcal{B}_s = \mathcal{B}_t$): Core-visible aggregate prefix unchanged. Theorem 4 applies: $\Delta S_{\mathrm{core}} = 0$.
- **Inter-domain intra-PLMN** ($\mathcal{B}_s \neq \mathcal{B}_t$, same PLMN): Aggregate prefix changes from $P_{\mathcal{B}_s}$ to $P_{\mathcal{B}_t}$. Core must update routing. $\Delta S_{\mathrm{core}} > 0$.
- **Inter-domain inter-PLMN** ($\mathcal{B}_s \neq \mathcal{B}_t$, different PLMN): Additional N+1 internetwork-layer coordination (roaming). $\Delta S_{\mathrm{core}}$ includes both intra-PLMN prefix update and inter-PLMN layer-peer coordination.

**Criterion** (for simulator):
- **5G**: Intra-domain if `source_upf == target_upf` (Xn criterion). Inter-domain if `source_upf != target_upf` (N2 criterion). Roaming if `source_plmn != target_plmn`.
- **6G-RUPA**: Intra-domain if both gNBs attach to the same GUPF or the same aggregate prefix $P_{\mathcal{B}}$. Inter-domain if the target's prefix $P_{\mathcal{B}'}$ differs. Roaming if target domain belongs to a different operator (different layer N).

---

## 5. Core State Delta $\Delta S_{\mathrm{core}}$ on Inter-Domain Crossings

When a handover crosses a domain boundary, the core's forwarding table must be updated to advertise the new prefix and possibly withdraw the old one (if no other UEs remain in the source domain).

**In 5G** (N2 handover):
- Each per-session FAR/TEID at the old UPF is released (forwarding table shrinks by 1 entry, cost $c_f$).
- Each per-session FAR/TEID at the new UPF is installed (forwarding table grows by 1 entry, cost $c_f$).
- If the handover moves an N9 session anchor, the anchor's per-session state grows by $c_f$.

For a single handover, the per-session impact is bounded (one session moved), but if we consider burst handovers (multiple users migrating from domain $\mathcal{B}_s$ to $\mathcal{B}_t$ in rapid succession), the core's table must accommodate them individually. The total state at the new anchor UPF grows by $K \cdot c_f$ where $K$ is the number of migrating sessions.

**In 6G-RUPA** (inter-domain renumbering):
- The target domain's aggregate prefix $P_{\mathcal{B}'}$ is advertised (already present in the core's FIB if the target domain exists, or installed as one new entry, cost $c_p$).
- The source domain's aggregate prefix $P_{\mathcal{B}}$ is withdrawn only if no UEs remain (forwarding table shrinks by $c_p$, a constant).
- No per-session entries are created or destroyed in the core.

**Theorem generalization**: $\Delta S_{\mathrm{core}}$ for a single inter-domain handover is:
- **5G**: $\Delta S_{\mathrm{core}}^{5G,N2} \approx 0$ (one session moved; amortized across all sessions in the domain, so negligible per handover if domain is large), but **aggregate anchor state grows linearly with burst events**: $\Delta S_{\mathrm{core}}^{\mathrm{anchor}} \approx c_f \cdot K$ where $K$ is the handover burst size.
- **6G-RUPA**: $\Delta S_{\mathrm{core}}^{\mathrm{RUPA}} \approx 0$ for a single handover (prefixes already present). On domain boundary relocation: $\Delta S_{\mathrm{core}} = c_p$ (one new prefix installed), independent of $K$.

**Formalization**:
Let $\mathcal{P}_{\mathrm{core}}(t)$ denote the set of prefixes in the core at time $t$. On a domain crossing:

$$\Delta S_{\mathrm{core}}(t) = c_p \cdot (|\mathcal{P}_{\mathrm{core}}(t)| - |\mathcal{P}_{\mathrm{core}}(t-1)|) \in \{-c_p, 0, +c_p\}$$

(bounded by one prefix added or removed; never scales with $N$ or handover rate $\lambda$).

---

## 6. Generalized Mobility Theorem and Corollary

### Theorem (Generalized Mobility Invariance)

**Statement**: Let $\mathcal{B}$ and $\mathcal{B}'$ be two attachment domains in a 6G-RUPA network. Consider a UE handover from $\mathcal{B}$ to $\mathcal{B}'$:

1. **Intra-domain case** ($\mathcal{B} = \mathcal{B}'$, $P_{\mathcal{B}}$ unchanged): The core forwarding state remains invariant ($\Delta S_{\mathrm{core}} = 0$), and the signaling cost is $\sigma_{\mathrm{RUPA}}^{\mathrm{intra}}$, independent of $\lambda$ and $N$.

2. **Inter-domain case** ($\mathcal{B} \neq \mathcal{B}'$, prefix changes to $P_{\mathcal{B}'}$): The core forwarding state is updated by $\Delta S_{\mathrm{core}} \in \mathcal{O}(1)$ (bounded by the cost to advertise one prefix), and the signaling cost is $\sigma_{\mathrm{RUPA}}^{\mathrm{inter}}$, independent of $\lambda$ and $N$.

3. **Contrast with 5G**: Under the same mobility scenario, 5G's core forwarding state at an anchor UPF grows by $\Delta S_{\mathrm{core}}^{5G} \in \mathcal{O}(K)$ where $K$ is the number of concurrent sessions (per-session FAR/TEID entries), and the signaling cost is $\sigma_{5G}^{\mathrm{N2}}$ per handover, multiplied by the number of sessions in a burst handover.

**Proof sketch** (informal, matching access.tex style):

*Intra-domain case*: By assumption, $P_{\mathcal{B}}$ is unchanged. The core's forwarding table routes all traffic destined to the domain aggregate via the same path to $\mathcal{B}$. The UE's renumbering within $\mathcal{B}$ affects only local gNB/GUPF bindings (source and target gNBs + upstream GUPF), not the core's routing table. Therefore, $\Delta S_{\mathrm{core}} = 0$, and $S_{\mathrm{fwd}}^{\mathrm{core}}$ is invariant with respect to $\lambda$. The signaling cost is bounded by the local renumbering exchange ($\sigma_{\mathrm{RUPA}}^{\mathrm{intra}}$, equation from §3.3), which is a constant independent of $N$ and $\lambda$.

*Inter-domain case*: The handover crosses into domain $\mathcal{B}'$ with prefix $P_{\mathcal{B}'}$. If $P_{\mathcal{B}'}$ is new to the core, one prefix entry must be installed ($\Delta S_{\mathrm{core}} = +c_p$). If $P_{\mathcal{B}}$ is withdrawn (no other UEs remain), one entry is removed ($\Delta S_{\mathrm{core}} = -c_p$). The net effect is $|\Delta S_{\mathrm{core}}| \leq c_p$, a constant. This constant is *independent of how many concurrent sessions are affected*: whether the UE is alone or one of many roaming users, the core's prefix set changes by the same amount. The signaling cost is $\sigma_{\mathrm{RUPA}}^{\mathrm{inter}}$ (equation from §3.4), also independent of $N$ and $\lambda$.

*Contrast with 5G*: In 5G, a handover from UPF$_{\mathrm{old}}$ to UPF$_{\mathrm{new}}$ requires a per-session FAR/TEID release at the old UPF and establishment at the new UPF. If $M$ sessions migrate in a burst, the new UPF's forwarding table grows by $M \cdot c_f$, so $\Delta S_{\mathrm{core}}^{5G} \in \mathcal{O}(M) = \mathcal{O}(N)$ in the worst case (all users roaming). The signaling cost is $\sigma_{5G}^{\mathrm{N2}}$ per handover, scaled by $M$ concurrent sessions, so total signaling is $M \cdot \sigma_{5G}^{\mathrm{N2}}$. Thus, both state and signaling scale with $N$ or burst size in 5G, whereas both remain bounded by topology in 6G-RUPA. $\square$

---

### Corollary (Roaming and Billing State Independence)

**Statement**: In both 5G and 6G-RUPA, per-session billing/context state $S_{\mathrm{ctx}}$ (e.g., Usage Records, URRs) is maintained separately from forwarding state $S_{\mathrm{fwd}}$. On roaming across a domain boundary:

- **5G Home-Routed**: The anchor UPF maintains $S_{\mathrm{ctx}}$ for the roaming user for billing purposes, in addition to forwarding state. Visited UPFs maintain transient forwarding state (N9 tunnel FAR/QER) and may also maintain visited-network usage records (visited CDR). The **total** context state at the anchor grows with $N$ and roaming burst size.

- **6G-RUPA inter-layer roaming**: Home layer maintains $S_{\mathrm{ctx}}$ (home CDR) for the roaming user; visited layer maintains $S_{\mathrm{ctx}}$ (visited CDR) for local usage tracking. The home layer does **not** maintain forwarding state for the roaming session (traffic is routed topologically via the visited domain's prefix $P_{\mathrm{visited}}$, not via a fixed anchor). Visited layer's forwarding state $S_{\mathrm{fwd}}$ is prefix-based, $\mathcal{O}(1)$ per domain, independent of roaming user count. The **separation of $S_{\mathrm{ctx}}$ and $S_{\mathrm{fwd}}$** makes billing exactly as trackable in 6G-RUPA as in 5G, while removing the per-session forwarding anchor.

**Implication**: 6G-RUPA's signaling-cost advantage ($\sigma_{\mathrm{roam}}^{\mathrm{RUPA}} < \sigma_{\mathrm{roam}}^{5G,HR}$) does not come at the cost of lost billing granularity. Both architectures can track per-user CDRs; 6G-RUPA simply avoids the anchoring overhead by keeping $S_{\mathrm{fwd}}$ topological and $S_{\mathrm{ctx}}$ distributed.

---

## 7. Summary Table: Signaling Costs and Scope

| Procedure | Architecture | Domain Crossing | $\sigma$ (bytes) | Scope | Notes |
|-----------|--------------|---|---|---|---|
| Handover (same anchor/UPF) | 5G Xn | Intra | 500 | 2 gNBs, 1 UPF | NGAP + PFCP Mod |
| Handover (different anchor) | 5G N2 | Inter | 1080 | 2 gNBs, 2 UPFs, SMF | NGAP + PFCP Release/Establish |
| Handover (intra-domain) | RUPA | Intra | 200 | 2 gNBs, 1 GUPF | Renumbering + EFCP rebind |
| Handover (inter-domain) | RUPA | Inter | 400 | 2 gNBs, 2 GUPFs, core routing | Renumbering + aggregate-prefix update |
| Roaming (HR) | 5G | Inter-PLMN | 1180 | 2 visited gNBs, 2 visited UPFs, home UPF, 2 SMFs | N9 session migration, home anchor fixed |
| Roaming (inter-layer) | RUPA | Inter-layer | 300 | 2 visited gNBs, 1 visited GUPF, home layer | Topological routing, no fixed anchor |

**Key metrics**:
- $\sigma_{\mathrm{RUPA}}^{\mathrm{intra}} / \sigma_{5G}^{\mathrm{Xn}} = 0.4$ (40% of Xn cost)
- $\sigma_{\mathrm{RUPA}}^{\mathrm{inter}} / \sigma_{5G}^{\mathrm{N2}} \approx 0.37$ (37% of N2 cost)
- $\sigma_{\mathrm{roam}}^{\mathrm{RUPA}} / \sigma_{\mathrm{roam}}^{5G,HR} \approx 0.25$ (25% of HR cost)

---

## 8. Simulator Implementation Requirements

The formal model above requires the following extensions to PLMN-GraphSim:

### 8.1 Types and State Tracking

- **Domain/Attachment type**: Add a domain/layer identifier to each UE and gNB (e.g., `domain_id :: Int`, `operator_id :: Int` for roaming scenarios). Classify handovers as intra- vs inter-domain at runtime.
- **Signaling counters**: Extend the metrics struct to track:
  - `sigma_5g_xn :: Int64` (cumulative bytes, Xn handovers)
  - `sigma_5g_n2 :: Int64` (cumulative bytes, N2 handovers)
  - `sigma_rupa_intra :: Int64` (cumulative bytes, intra-domain renumbering)
  - `sigma_rupa_inter :: Int64` (cumulative bytes, inter-domain renumbering)
  - `sigma_roam_5g :: Int64` (roaming signaling, 5G)
  - `sigma_roam_rupa :: Int64` (roaming signaling, RUPA)
- **Per-handover event logging**: Log the procedure type, domain crossing classification, and $\sigma$ value for each handover event (for per-handover analysis, not just cumulative).

### 8.2 Handover Classification Logic

- **In `handle_handover_5g!`**:
  - Determine if anchor UPF changes (same = Xn, different = N2).
  - Add $\sigma_{5G}^{\mathrm{Xn}}$ or $\sigma_{5G}^{\mathrm{N2}}$ (500 or 1080 bytes) to the appropriate counter.
  - Track both intra- and inter-PLMN roaming separately.
  
- **In `handle_handover_6grupa!`**:
  - Determine if domain changes (same = intra, different = inter).
  - Add $\sigma_{\mathrm{RUPA}}^{\mathrm{intra}}$ or $\sigma_{\mathrm{RUPA}}^{\mathrm{inter}}$ (200 or 400 bytes) to the appropriate counter.
  - Track roaming separately from intra-MNO handovers.

### 8.3 Roaming Path Logic

- **Roaming detection**: If `target_ue.operator_id != source_ue.operator_id`, classify as roaming.
- **5G Home-Routed**: Session anchors at home-PLMN UPF; visited UPF routes via N9. Add $\sigma_{\mathrm{roam}}^{5G,HR}$ (1180 bytes) per roaming handover.
- **6G-RUPA inter-layer**: Home layer maintains accounting state; visited layer maintains forwarding state (topological prefix). Add $\sigma_{\mathrm{roam}}^{\mathrm{RUPA}}$ (300 bytes) per roaming handover.

### 8.4 CSV Reporting

- Extend `mobility_evolution_*.csv` to include columns:
  - `cumulative_sigma_5g_xn`, `cumulative_sigma_5g_n2`, `cumulative_sigma_rupa_intra`, `cumulative_sigma_rupa_inter`, `cumulative_sigma_roam_5g`, `cumulative_sigma_roam_rupa`
  - Per-timestamp snapshot of each counter (for plotting over time).

### 8.5 Test Assertions

- **Xn handover**: Assert that `sigma_5g_xn` increments by exactly 500 bytes.
- **N2 handover**: Assert that `sigma_5g_n2` increments by exactly 1080 bytes.
- **RUPA intra-domain**: Assert that `sigma_rupa_intra` increments by 200 bytes and `sigma_rupa_inter` does not change.
- **RUPA inter-domain**: Assert that `sigma_rupa_inter` increments by 400 bytes.
- **Roaming**: Assert that roaming handovers trigger the correct $\sigma_{\mathrm{roam}}$ counter and that accounting state ($S_{\mathrm{ctx}}$) is tracked in both home and visited layers.

---

## 9. Limitations and Future Work

- **Message overhead estimation**: Byte counts for 3GPP procedures (Xn, N2, roaming) are extracted from spec procedure definitions but may vary by implementation (TLV ordering, optional IEs, padding). The values given are conservative (designed to be slightly above typical implementations) and serve as a baseline for comparison.

- **RINA operationalization**: 6G-RUPA's EFCP rebinding and renumbering procedures are described qualitatively in access.tex and grounded in RINA's reference model, but no formal 3GPP-style procedural specification exists yet. The $\sigma_{\mathrm{RUPA}}$ values are derived from architectural principles (local scope, no per-session forwarding entries) and are validated by simulation against realistic topologies.

- **Packet loss and latency**: This model captures signaling event counts and message sizes, not transient packet loss or latency during handover state-machine progression. These remain open research questions (access.tex line 1623–1626) and are out of scope for this formal model.

- **Control-plane mapping overhead** (PFCP shim): The GUPF's adaptation layer translates per-session PFCP rules (from 5G control plane) into RINA EFCP flow allocations, which is $\mathcal{O}(N)$ with respect to session count. This is orthogonal to the data-plane forwarding state ($\mathcal{O}(1)$) and is not included in the signaling-cost model (which focuses on user-plane handover events, not control-plane session setup). Future work may quantify this shim's latency under high session churn.

---

## References and Citations

- **access.tex (submitted IEEE Access paper)**:
  - Equation 1 (node state model): Line 851
  - Theorem 4 (conditional mobility invariance): Line 953
  - §V-D (mobility and topological addressing): Line 1561–1592
  - IPC model and N+1 layers: Line 426–433

- **3GPP Specifications**:
  - 3gpp-ts-38401-i00 (gNB procedures): Handover Request/Acknowledge (§ 8.9.4)
  - 3gpp-ts-23-501-j50 (5G system architecture): Session modification (§ 5.8.2.9), roaming (§ 4.2.8.2.3 and § 5.8.2.10)
  - 3gpp-ts-29244-h50 (PFCP protocol): Session Release/Establishment/Modification (§ 7.2.1–7.2.6, TLV definitions)

- **RINA Reference Model**:
  - Interina (2013-01) — RINA reference model definitions (renumbering, EFCP, port, DIF/IPC Process)
  - J. Day et al., "Patterns in Network Architecture," (cited in access.tex) — architectural rationale for topological addressing and renumbering.

---

**Document version**: 1.0 (June 2024)  
**Status**: Ready for integration into INFOCOM mobility paper Section 3 (Generalized Mobility Model) and for simulator implementation in PLMN-GraphSim.
