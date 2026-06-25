# Mobility Results — Validation & Interpretation

Purpose: confirm the national handover results are physically/architecturally
correct and explain *why* each number comes out as it does, before building
roaming on top. Distinguishes genuine simulation findings from quantities that
are fixed by assumption.

---

## 1. What the simulation actually measures

Per scenario: 1000 persistent mobile eMBB agents on the full OpenCellID topology;
each tick (dt) the serving gNB is recomputed (nearest gNB); any change is a
handover, classified Xn/N2 (anchor-UPF change) and intra/inter-domain (UPF-cluster
change), each charged its σ. Outputs: handover count + rate, Xn/N2 mix, per-class
and total signaling bytes.

---

## 2. Handover rate — sublinear in speed (explained)

Controlled sweep, **same** model (Gauss-Markov α=0.85), only speed varies, Spain
(46,396 gNBs, 20 UPFs):

| speed km/h | HO/user/hr | HO per km of path |
|---|---|---|
| 5 | 6.2 | 1.233 |
| 20 | 23.0 | 1.149 |
| 50 | 50.2 | 1.003 |
| 80 | 71.5 | 0.894 |
| 120 | 79.8 | 0.665 |

If cell-crossing were purely geometric, HO/km-of-path would be **constant** (a
straight line crosses a Voronoi tessellation at a fixed rate per unit length) and
HO/hr would be exactly linear in speed. It is not: HO/km falls from 1.23 (5 km/h)
to 0.67 (120 km/h).

**Cause — spatial gNB-density heterogeneity, not a model artifact** (the model is
identical across rows). Agents are placed uniform-over-gNBs (the population-
weighting fallback), which concentrates them where gNBs are dense (cities). A slow
agent travels ~1.7 km in 1200 s and stays inside that dense urban pocket, where
cells are sub-km → high HO/km. A fast agent travels ~40 km, leaving the city into
sparse rural cells → lower *average* HO/km. So speed and sampled-density are
confounded: faster agents sample a lower mean density.

This is a real deployment effect (urban users hand over more often per km but move
less), but it means the headline cannot claim "handover rate is linear in speed."
The honest statement: handover rate increases with speed, sublinearly, because
faster users traverse lower-density regions on average.

### Geometric cross-check
Spain density λ = 46396 / 505000 = 0.092 /km². Poisson-Voronoi straight-line
crossing rate = (4/π)√λ = 0.386 HO/km. Measured HO/km (0.67–1.23) sits **above**
this because (a) real gNBs cluster super-Poisson (urban hotspots), and (b)
placement over-weights dense areas. The homogeneity control (§5) tests whether the
simulator reproduces 0.386 on a uniform field — isolating heterogeneity as the
cause of the real-data slope.

---

## 3. Xn/N2 mix — ~99/1, grows slightly with speed (explained)

N2 (anchor-UPF change) occurs only when a handover also crosses a K-means UPF
cluster boundary. Observed N2 fraction: 0.0% (5 km/h) → 0.36% (120 km/h).

- **Low overall** because UPF regions are large (20 clusters over Spain): the
  probability that two adjacent gNBs lie in different clusters is small, ≈
  √(N_upf/N_gnb) ≈ 2% as an upper bound for uniform sampling of all adjacencies.
- **Below 2% and speed-dependent** because slow agents barely move and therefore
  under-sample UPF-region boundaries; only longer trips (higher speed) cross them.
- **Tunable by UPF count**: N2 fraction is set by the number/placement of UPFs, a
  deployment parameter — not an emergent property. The paper must justify the UPF
  count from real deployment and ideally sweep it.

This matches operational reality: the large majority of handovers are intra-anchor
(Xn), a small minority are N2.

---

## 4. The 66.7% advantage is set by the per-event constants, not emergent

Advantage = 66.7% at **every** speed, every model, both countries. This is not a
coincidence and not an independent simulation result:

- With the mix ~99% intra/Xn, total cost ≈ N_HO × σ_intra/Xn.
- advantage ≈ 1 − σ_RUPA_intra / σ_5G_Xn = 1 − 200/600 = **0.667**.
- The rare N2/inter-domain term (1 − 200/1150 = 0.826) nudges the blend upward
  only slightly because the event fraction is small.

**Implication.** The magnitude of the advantage rests entirely on the two
constants σ_Xn = 600 B and σ_intra = 200 B (and secondarily 1150/200 for rare
N2/inter-domain events). The
simulation does **not** validate the percentage; it validates:
1. that realistic national mobility produces an Xn-dominated mix (so the intra
   ratio is what matters), and
2. the **absolute** signaling load at national scale (MB/hr), which scales with
   users × handover rate and is the deployment-relevant figure.

The paper must therefore (a) defend 600 vs 200 rigorously from 3GPP/RINA
procedures (already in `mobility-formal-model.md`), and (b) frame the contribution
as *mix + absolute load + scaling*, presenting the % as a direct consequence of
the per-procedure cost ratio, with a sensitivity analysis over the σ constants.

---

## 5. Homogeneity control (isolates heterogeneity)

Same GM speed sweep on a synthetic uniform gNB field (46,396 gNBs over a 711 km
box at Spain's mean density λ=0.092). Geometric prediction (4/π)√λ = 0.386 HO/km.

| speed km/h | HO/km path (synthetic uniform) | HO/km path (real Spain) |
|---|---|---|
| 5 | 0.028 | 1.233 |
| 20 | 0.191 | 1.149 |
| 50 | 0.402 | 1.003 |
| 80 | 0.391 | 0.894 |
| 120 | 0.386 | 0.665 |

**Conclusions (three at once):**

1. **Simulator geometry is correct.** On the uniform field at speeds ≥50 km/h,
   HO/km converges to 0.386–0.402 = exactly the Poisson-Voronoi prediction
   (4/π)√λ. Handover detection is geometrically sound.
2. **The real-data slope is spatial heterogeneity — proven by the opposite
   sign.** Uniform field: HO/km *rises* with speed (0.028→0.386). Real topology:
   HO/km *falls* (1.233→0.665). Opposite directions; the only difference is
   density heterogeneity + placement. On the real topology slow agents sit in
   dense urban cells (sub-km → over-cross); on the uniform field slow agents
   simply travel <1 cell and under-cross.
3. **Low-speed undersampling.** At 5 km/h an agent moves ~1.7 km in 1200 s — less
   than one mean cell diameter (~3.7 km). Only 47 handovers across 1000 agents on
   the uniform field. The real-topology pedestrian numbers (2055 HO) are therefore
   dominated by *urban placement density*, not by mobility. Pedestrian scenarios
   need a longer duration (or explicit framing) to be statistically meaningful.

The N2 fraction on the uniform field at high speed is 1.8–2.0%, matching the
√(N_upf/N_gnb) = 2.08% estimate from §3 — independent confirmation that the
Xn/N2 split is governed by UPF count as predicted. The real topology's lower
0.36% reflects clustered UPF regions + placement, not a different mechanism.

---

## 6. Checks that pass cleanly

- inter-domain (RUPA) event count == N2 (5G) event count, by construction (same
  domain crossing triggers both). Verified all scenarios.
- handover_count == Xn + N2 events (no double counting). Verified.
- USA rates ≈ 2.8× lower than Spain at matched speed, tracking the ≈8× lower gNB
  density (USA 0.012 vs Spain 0.092 /km²). Cross-country physical consistency.
- Both mobility models (RWP, Gauss-Markov) give the same advantage — robustness to
  model choice.

---

## 7. Actions for paper-grade evaluation

1. **Decide agent placement deliberately.** Either fix population-weighting (wire
   municipality polygons into the topology struct) for realism, or use
   uniform-over-area for clean geometry. Document the choice; it drives the
   rate-vs-speed shape.
2. **Report rate-vs-speed honestly** as sublinear, with the heterogeneity
   explanation, or normalize by sampled local density.
3. **σ sensitivity analysis.** Show advantage vs the σ_intra/σ_Xn ratio so the
   result's dependence on the constants is explicit.
4. **Sweep UPF count** to show the Xn/N2 mix and how it shifts the blended cost.
5. **Lead with absolute national signaling load** (MB/hr for 5G vs RUPA at a given
   mobile-user population), the deployment-relevant headline, with the % as the
   per-event ratio it is.
