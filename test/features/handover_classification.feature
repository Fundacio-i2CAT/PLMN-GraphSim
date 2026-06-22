Feature: 5G/6G-RUPA Handover Classification and Signaling Cost Tracking

  Background: Single MNO with two UPFs serving multiple gNBs
    Given a simulation with two UPFs (anchor points)
    And gNB 1 and gNB 2 served by UPF 1
    And gNB 3 served by UPF 2
    And an agent with active PDU sessions

  # ============ 5G Xn Handover (same anchor UPF) ============
  Scenario: Xn handover - UE moves between gNBs sharing same anchor UPF
    When UE hands over from gNB 1 to gNB 2 (both with anchor UPF 1)
    Then handover is classified as Xn (same anchor)
    And sigma_5g_xn counter increments by 500 bytes
    And sigma_5g_n2 counter does not change
    And session anchor_upf_index remains UPF 1
    And handover_count increments to 1

  # ============ 5G N2 Handover (anchor UPF changes) ============
  Scenario: N2 handover - UE moves to gNB served by different anchor UPF
    When UE hands over from gNB 1 (anchor UPF 1) to gNB 3 (anchor UPF 2)
    Then handover is classified as N2 (anchor change)
    And sigma_5g_n2 counter increments by 1080 bytes
    And sigma_5g_xn counter does not change
    And session anchor_upf_index changes from UPF 1 to UPF 2
    And handover_count increments to 1

  # ============ 5G Home-Routed Roaming (inter-PLMN, HR) ============
  Scenario: Home-Routed roaming - UE roams to visited PLMN with HR model
    When UE hands over from home PLMN gNB to visited PLMN gNB
    And roaming mode is Home-Routed (traffic through H-SMF anchor)
    Then handover is classified as HR roaming
    And sigma_roam_5g increments by 1180 bytes
    And V-SMF in visited PLMN routes data via N9 to H-UPF anchor
    And H-SMF in home PLMN maintains session anchor
    And handover_count increments to 1

  # ============ 5G Local Breakout Roaming (inter-PLMN, LBO) ============
  Scenario: Local Breakout roaming - UE roams with data breaking out locally
    When UE hands over from home PLMN gNB to visited PLMN gNB
    And roaming mode is Local Breakout (data exits at V-UPF)
    Then handover is classified as LBO roaming
    And sigma_roam_5g_lbo increments by 800 bytes
    And V-SMF in visited PLMN establishes V-UPF anchor for data plane
    And H-SMF in home PLMN maintains only control plane context
    And traffic does not backhaul through home network
    And handover_count increments to 1

  # ============ 6G-RUPA Intra-domain Handover ============
  Scenario: 6G-RUPA intra-domain handover - UE renumbered within same GUPF
    When using 6G-RUPA architecture
    And UE hands over from gNB 1 to gNB 2 (both attach to same GUPF)
    Then handover is classified as intra-domain renumbering
    And sigma_rupa_intra increments by 200 bytes
    And sigma_rupa_inter counter does not change
    And core forwarding table (aggregate prefix) size unchanged
    And UE acquires new topological address within same domain prefix
    And handover_count increments to 1

  # ============ 6G-RUPA Inter-domain Handover ============
  Scenario: 6G-RUPA inter-domain handover - UE renumbered to different GUPF domain
    When using 6G-RUPA architecture
    And UE hands over from gNB 1 (GUPF 1) to gNB 3 (GUPF 2)
    Then handover is classified as inter-domain renumbering
    And sigma_rupa_inter increments by 400 bytes
    And sigma_rupa_intra counter does not change
    And core routing table installs new aggregate prefix entry
    And UE acquires new topological address in destination domain
    And old domain prefix withdrawn if no UEs remain
    And handover_count increments to 1

  # ============ 6G-RUPA Inter-layer Roaming (N+1 recursion) ============
  Scenario: 6G-RUPA inter-layer roaming - UE moves between MNO layers
    When using 6G-RUPA architecture
    And UE hands over from home layer (operator 1) to visited layer (operator 2)
    Then handover is classified as inter-layer roaming
    And sigma_roam_rupa increments by 300 bytes
    And home layer maintains billing context (S_ctx URR equivalent)
    And visited layer maintains forwarding state (S_fwd topological prefix)
    And no per-session forwarding anchor exists
    And N+1 internetwork layer routes traffic topologically
    And handover_count increments to 1

  # ============ Signaling Cost History and Metrics Export ============
  Scenario: Multiple handovers accumulate correct sigma costs
    When sequence of handovers occurs:
      | type | count | cost_per | total |
      | Xn   | 5     | 500      | 2500  |
      | N2   | 3     | 1080     | 3240  |
      | HR   | 1     | 1180     | 1180  |
      | LBO  | 2     | 800      | 1600  |
    Then history_sigma_5g_xn tracks cumulative bytes (2500)
    And history_sigma_5g_n2 tracks cumulative bytes (3240)
    And history_sigma_roam_5g_hr tracks cumulative bytes (1180)
    And history_sigma_roam_5g_lbo tracks cumulative bytes (1600)
    And mobility_evolution_*.csv includes all sigma columns
    And CSV rows match timestamped history snapshots

  # ============ Billing Context Independence (S_ctx orthogonal to S_fwd) ============
  Scenario: Billing state tracked independently from forwarding state
    When roaming occurs (5G HR or 6G-RUPA roaming)
    Then home network maintains billing/accounting context (S_ctx)
    And visited network maintains forwarding/routing state (S_fwd)
    And S_ctx size is independent of where S_fwd resides
    And both HR and LBO can track per-UE CDRs
    And billing granularity is preserved across handovers
