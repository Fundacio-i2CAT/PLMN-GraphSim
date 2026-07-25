Feature: Handover & crossing signaling cost — 5G vs 6G-RUPA
  # LIVING SPEC. This file is the agreed, current statement of the σ model and the
  # graph-of-graphs claims. It supersedes the earlier draft, which had stale
  # constants (roam 1180, inter 400) and the WRONG core-prefix model (install/
  # withdraw a core route per move). Both are corrected below.
  #
  # σ constants (single source; keep in sync with test/TestFixtures.jl and
  # src/Simulation/{Handover,Layers,NTN}.jl):
  #   Xn (intra-domain, same anchor) ............ 600 B
  #   N2 (inter-domain, anchor preserved) ....... 1150 B
  #   6G-RUPA renumber (intra == inter, FLAT) ... 200 B
  #   crossing 5G, :reestablish (deployed) ...... 3250 B  + session break + acct reloc
  #   crossing 5G, :ideal_ho (sensitivity) ...... 1300 B  no break
  #   6G-RUPA crossing entry .................... 450 B   0 breaks (then 200 B/move)
  #   NTN sat->sat switch: 5G 1150 / RUPA 200
  # Core forwarding-state writes per handover: 5G = sessions x scale_factor; RUPA = 0.

  Background:
    Given a two-tier single operator: gNB 1,2 on edge UPF 1, gNB 3 on edge UPF 2
    And both edge UPFs anchored at PSA 1 (SSC mode 1, anchor pinned)
    And an agent with active PDU sessions

  # ---- Per-event σ (the core table) ----
  @wired
  Scenario: Xn handover — same edge UPF
    When the UE moves from gNB 1 to gNB 2 (same edge UPF 1)
    Then it is classified intra-domain, climb 0
    And sigma_5g_xn increments by 600 and sigma_5g_n2 is unchanged
    And sigma_rupa_intra increments by 200
    And handover_count increments by 1

  @wired
  Scenario: N2 handover — different edge UPF, anchor preserved
    When the UE moves from gNB 2 (edge UPF 1) to gNB 3 (edge UPF 2)
    Then it is classified inter-domain, climb 0
    And sigma_5g_n2 increments by 1150 and sigma_5g_xn is unchanged
    And sigma_rupa_inter increments by 200
    And the session anchor_upf_index remains PSA 1

  @wired
  Scenario: 6G-RUPA renumber is FLAT — inter costs the same as intra
    When the UE renumbers within a domain, then across a domain boundary
    Then both charge 200 B (the destination aggregate prefix already exists)
    And no core forwarding entry is installed or withdrawn (delta S_core = 0)

  # ---- The O(n) vs O(1) headline ----
  @wired
  Scenario: 5G rewrites per-session core state; 6G-RUPA writes none
    Given an agent with 2 sessions and scale_factor 1000
    When an N2 handover occurs
    Then core_writes_5g increments by 2 * 1000
    And core_writes_rupa stays 0 at every level

  # ---- SSC mode 1: anchor pinning + path stretch ----
  @wired
  Scenario: PSA-region crossing stays N2, anchor pinned, stretch accumulates
    Given edge UPF 3 anchored at a second PSA 2
    When the UE moves edge UPF 2 -> edge UPF 3 (crossing PSA region)
    Then it is still N2 1150 (not a PSA relocation): sigma_5g_psa stays 0
    And ho_l3 increments as a geometric marker only
    And the anchor stays PSA 1 and anchor_dist_5g_sum > anchor_dist_opt_sum
    And acct_reloc_5g and acct_reloc_rupa stay 0 (SSC-1 intra-PLMN)

  # ---- Roaming / member crossing (operator change) ----
  @wired
  Scenario: Border crossing, deployed reality (:reestablish)
    When the UE crosses from operator 1 to operator 2
    Then sigma_roam_5g increments by 3250 and the session breaks (scaled)
    And acct_reloc_5g increments (charging context rebuilt)
    And sigma_roam_rupa increments by 450 with 0 breaks (flow survives)

  @wired
  Scenario: Border crossing, idealized inter-PLMN HO (:ideal_ho sensitivity)
    When the UE crosses operators under :ideal_ho semantics
    Then sigma_roam_5g increments by 1300 and no session breaks
    And sigma_rupa is unchanged relative to :reestablish (architecture-invariant)

  @wired
  Scenario: Roaming path-stretch is the country-scale hairpin
    When a roamer hands over while abroad (serving operator != anchor operator)
    Then the sample lands in the roam bucket, not the domestic bucket
    And roam_dist_5g_sum is the visited-edge -> pinned-home-PSA distance (100s of km)
    And roam_dist_opt_sum uses the nearest aggregate (near 0)

  # ---- Federation (K operators) ----
  @wired
  Scenario: K-ary composition offsets, tags, and O(K) membership
    Given K operator fields composed into one topology
    Then edge/PSA indices are offset per preceding member and tagged by operator
    And municipalities dedupe by (code, name) so population weight counts once
    And membership is K enrollments vs 5G's K*(K-1)/2 bilateral agreements

  # ---- Graph-of-graphs (recursive internetworking) ----
  @wired
  Scenario: Climb depth classifies the move (one rule, all cases)
    Given member layers under exchange layers under a root
    When the UE moves within a member / to a sibling member / across exchanges
    Then classify_move returns climb 0 / climb 1 / climb 2 respectively
    And sigma_rupa is FLAT in climb depth (450 entry regardless of depth)

  @wired
  Scenario: Topological address makes climb a prefix comparison
    Given hierarchical addresses root.exchange.member.psa.edge
    Then two nodes share a prefix exactly up to their first common layer
    And climb == member-path-length - shared-prefix-length
    And edges under one PSA share the aggregate prefix, differ only in the suffix

  @wired
  Scenario: charge_move! reproduces legacy dispatch_handover! exactly
    When the same move set is driven through both paths on twin states
    Then every sigma / event / break counter matches
    # This equivalence is the linchpin: it lets sigma be asserted once centrally.

  # ---- NTN member (§7.5.2) ----
  @wired
  Scenario: Terrestrial <-> satellite crossing uses its own buckets
    When the UE crosses terrestrial <-> NTN
    Then sigma_ntn_cross_* is charged (3250/1300 vs 450) not the §7.4 roam counters
    And a satellite->satellite switch is N2-class 1150 (5G) vs 200 (RUPA)

  @wired
  Scenario: SGP4 propagation is validated against LEOPath
    Given the same TLE set LEOPath uses
    Then sub-satellite points agree to <0.2° lat, <0.06° lon across fixtures

  # ---- Billing orthogonality (§7.3) ----
  @wired
  Scenario: Same granularity, different key — RUPA key invariant under renumber
    When every user does a PSA-relocating move
    Then the 5G accounting key (user, PSA) relocates; the RUPA key (AP-name) does not
    And per-user billing totals are identical in both

  # ---- Out of scope, documented ----
  @future @not-implemented
  Scenario: Local Breakout roaming
    # HR only is modelled (operators default to HR for CDR tracking). LBO is the
    # contrast operators avoid; no sigma_roam_5g_lbo counter exists.

  @future @not-modelled
  Scenario: Single-radio interruption gap
    # RINA multihoming/0-loss assumes >=2 radios. A single-radio UE has a radio
    # association gap on every handover, orthogonal to the architecture (hits 5G
    # and RUPA equally). Network-layer 0-loss (EFCP port-ids) still holds. Not
    # charged in the sim; would apply symmetrically. See memory + roaming notes.
