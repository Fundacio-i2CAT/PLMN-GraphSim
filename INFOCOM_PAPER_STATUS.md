# INFOCOM Mobility Paper — Status

**Paper**: "Beyond Static Aggregation: Handover and Roaming Signaling Cost of 6G-RUPA vs 5G Under Mobility"
**Deadline**: 2026-07-24 (INFOCOM)
**Branch**: feature/mobility-handover-sigma (Sergio reviews & commits)

---

## Where we are

National-scale mobility evaluation **works on the full real topologies** — Spain
(46,396 gNBs) and USA (113,210 gNBs), no subsampling. The σ signaling-cost model
is validated end-to-end; the generalized mobility theorem is derived; tests are
green (213) and now actually assert motion + integrated dispatch.

### Results (primary evidence)

Spain national (20 UPFs), 1000 mobile agents, 1200 s:

| Scenario | HO/user/hr | 5G | 6G-RUPA | advantage |
|---|---|---|---|---|
| Pedestrian 5 km/h | 5.5 | 1.11 MB | 0.37 MB | 66.7% |
| Urban 50 km/h | 44.3 | 8.90 MB | 2.97 MB | 66.7% |
| Highway 120 km/h | 83.8 | 16.86 MB | 5.62 MB | 66.6% |

USA national (30 UPFs):

| Scenario | HO/user/hr | 5G | 6G-RUPA | advantage |
|---|---|---|---|---|
| Pedestrian 5 km/h | 1.8 | 0.37 MB | 0.12 MB | 66.6% |
| Urban 50 km/h | 16.6 | 3.33 MB | 1.11 MB | 66.7% |
| Highway 120 km/h | 37.2 | 7.46 MB | 2.49 MB | 66.7% |

Key properties (both countries): handover rate scales with speed and gNB density
(Spain ~2.8× USA, tracks the ~8× density gap); Xn/N2 split ≈ 99/1; RUPA
inter-domain events == 5G N2 events by construction; advantage ~66.7% invariant
to speed, mobility model, and country (it is the per-event cost ratio).

Reproduce: `julia --project run_national.jl spain` / `... usa`.

---

## What changed from the earlier (wrong) plan

Earlier status claimed national scale "produces 0 handovers" and proposed
documenting it as a limitation, falling back to a 4-gNB minimal topology. **That
was a mobility bug, not a deployment limit.** Root causes, now fixed:

1. **Random Waypoint never moved** — the pause/move state machine re-entered pause
   after every waypoint pick and returned the start location forever. Agents had
   zero displacement.
2. **Gauss-Markov only diffused** — mean-zero velocity update; no sustained
   direction. Now ballistic (persistent heading, constant speed).
3. **RUPA inter-domain path was dead** — Core.jl mutated `current_domain` before
   the 6G-RUPA call, so it always saw equal domains → always intra.
4. **Handovers double-counted** — both `handle_handover_5g!` and
   `handle_handover_6grupa!` bumped `handover_count`. Extracted single
   `dispatch_handover!` entry point (correct order, count once).

The tests were green through all of this because the mobility test only asserted
an **upper bound** (`displacement ≤ cap`, which 0 satisfies) and never tested the
integrated dispatch. Replaced with motion assertions (path ≈ speed × time) and a
`dispatch_handover!` integration test; these fail on the old code.

---

## Artifacts

- `docs/mobility-formal-model.md` — σ derivation (Xn 600 / N2 1150 / intra 200 /
  inter 400 / roam HR 1180 / roam RUPA 300 B), generalized mobility theorem,
  3GPP/RINA grounding.
- `docs/mechanism-and-evaluation-strategy.md` — mechanism + national results.
- `infocom-mobility-paper/outline.md` — living 8-section outline (national-scale
  results in §5–6).
- `run_national.jl` — parametric national eval (spain|usa).
- `test/MobilityTests.jl`, `test_mobility_displacement.jl` — motion + dispatch tests.
- `test/features/handover_classification.feature` — Gherkin spec (corrected;
  currently documentation-only — not wired to a runner).

---

## Next

1. **Roaming (plan §6)** — contribution #3, not yet exercised. `sigma_roam_5g`
   (Home-Routed) and `sigma_roam_rupa` (N+1 internetwork) counters exist but the
   national sim is single-operator. Build terrestrial-to-terrestrial roaming
   first, validate, then reuse for satellite/NTN.
2. **Figures & CSV** — `run_national.jl` doesn't persist results; need
   forwarding-state-over-time, σ cumulative, Xn/N2 split, advantage-vs-speed plots.
3. **Population-weighted placement** — currently a silent uniform-over-gNBs
   fallback (municipality polygons not attached to the topology struct). Enabling
   it concentrates agents in cities; expected to strengthen the result.
4. **Wire up Gherkin** (optional) — add step definitions so the .feature can't
   drift again, per the TDD/Gherkin workflow.
5. **Prose** — draft once roaming results land.

---

## Cleanup (dead workaround scripts to delete)

`run_spain_coarse_subset.jl`, `run_spain_focused.jl`, `run_spain_forced_handover.jl`,
`run_spain_minimal_pattern.jl`, `run_mobility_eval*.jl` — all were attempts to work
around the mobility bug (subsampling, forced handovers). Superseded by
`run_national.jl`. `run_minimal_topology.jl` kept as the mechanism micro-check.
