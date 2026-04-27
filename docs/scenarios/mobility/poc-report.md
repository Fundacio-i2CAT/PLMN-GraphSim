# Mobility PoC Report

## Why This Change Exists

The current simulator validated the stationary case: users attach once, keep their PDU sessions, and forwarding state is measured at steady state. That is enough for the scalability-paper result on static UPF/GUPF state, but it does not exercise the next research question: what changes when UEs move and the network must signal handovers?

The goal of this PoC is deliberately narrow: add enough mobility to compare signaling pressure between 5G and 6G-RUPA without yet modeling full handover latency, packet loss, AMF/SMF load, or exact 3GPP message sequences.

## What Changed

- Added a mobility configuration path through `SimConfig`, defaulting to disabled so existing stationary experiments remain reproducible.
- Added a `MobilityModel` abstraction with `NoMobility` and a first `RandomWaypoint` implementation.
- Added a mobile eMBB lifecycle that periodically updates UE position, re-selects the nearest gNB, and detects cell changes.
- Added generic handover handlers:
  - 5G migrates the UE session contexts between serving UPFs when the serving UPF changes.
  - 6G-RUPA records a local renumbering event on every cell change, without growing forwarding tables.
- Added cumulative metrics for handovers and signaling events, plus a `mobility_evolution_*.csv` export when mobility is enabled.

## Why These Design Choices

- Mobility is opt-in because the paper's existing stationary evaluation should remain unchanged by default.
- The first mobility model is simple because the immediate research need is to exercise handover signaling paths, not to claim realism of traces yet.
- The 5G handler only counts generic inter-UPF signaling for now because exact Xn/N2 message accounting belongs in the next phase.
- The 6G-RUPA handler counts local renumbering events rather than per-UE forwarding state because that is the core architectural claim: mobility should not create UPF-like per-session tunnel state.
- Metrics are cumulative per sampling tick so post-processing can compute both totals and rates by differencing.

## Tests Performed

- Added `test/MobilityTests.jl` with 18 tests covering:
  - legacy constructors keep mobility disabled by default,
  - `NoMobility` is a no-op,
  - `RandomWaypoint` respects the configured movement bound,
  - 5G handover migration moves session contexts between UPFs and increments signaling counters,
  - 6G-RUPA renumbering increments only on real cell changes.
- Ran the package tests. Result: mobility tests pass and existing functional tests pass. The only full-suite failure is the pre-existing Aqua stale-dependency check for unused `StatsPlots`/`Plots`, unrelated to this work.
- Ran a synthetic smoke test with 4 gNBs, 2 UPFs, 20 mobile agents, and aggressive mobility. It produced handovers, migrated 5G sessions between UPFs, and populated mobility histories as expected.

## Next Steps

1. Split 5G signaling into Xn vs N2 handovers using old/new gNB and anchor UPF metadata.
2. Add message-count and byte-count models for NGAP and PFCP handover procedures, so the comparison becomes signaling volume rather than generic event count.
3. Make Random Waypoint stateful with explicit destinations and pause times.
4. Add at least one smoother or more realistic model, likely Gauss-Markov first, then population-aware movement or trace replay.
5. Add plots for cumulative signaling, signaling rate, and signaling per handover for 5G vs 6G-RUPA.
6. Later, add latency and packet-loss windows once the signaling model is stable.

These steps move the simulator from a PoC toward a paper-quality mobility evaluation while keeping the scope controlled.
