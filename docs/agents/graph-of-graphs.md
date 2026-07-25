# Graph-of-graphs layer model

How `src/Simulation/Layers.jl` represents a federation as a DAG of layers, and
how handover classification generalizes. Terminology is 6G-RUPA's: **GUPF** (not
"IPC process"), **layer** (not "DIF").

## The four types

| Type | Is | Key field |
|------|----|-----------|
| `GUPF` | one `(node, layer)` participation | `forwarding_table` (scoped to the layer) |
| `Layer` | one graph over GUPFs | `gupfs`, `edges`, `border_node` |
| `LayerStack` | the DAG of layers | `floats_over`, `parents`, `member_of` |
| `Attachment` | a UE's `(member layer, edge domain)` | — |

A physical node in *k* layers hosts *k* GUPF instances, each with its own
forwarding table. That is the recursion: a PSA is a `:psa` GUPF in its member
layer **and** a `:border` GUPF in the federation layer above — same box, two
tables. `:psa` (3GPP) and `:border` (generic "represents my layer upward") are
distinct roles that coincide only in the terrestrial two-tier case; an NTN
member's border is a satellite, an exchange's border is another border.

## From topology to stack

`build_layer_stack(topology)` reads a composed multi-operator `NetworkTopology`:
- one **member layer** per operator tag — GUPFs at its edge UPFs (`:edge`) and
  PSAs (`:psa`);
- one **internetwork layer** with a `:border` GUPF per member PSA.

`add_federation_layer!(stack, lowers)` stacks further layers (exchange layers, a
root over exchanges — the N+1/N+2 case). `add_member_layer!` + `enroll!` add a
member after the fact (e.g. an NTN constellation) — O(1) per join.

The hierarchy demo (`runs/hierarchy.jl`): members 1,3,4 → `exchange-es`;
members 2,5 → `exchange-pt`; both exchanges → `eu-root`. Three levels.

## Classification = one recursive climb

`classify_move(stack, old, new)` replaces the enumerated Xn/N2/roaming/NTN switch
with a single rule: **climb the DAG from both endpoints to the first common
layer.** Climb depth = event class.

```
same layer, same domain → :intra    (climb 0)   ~ 5G Xn
same layer, diff domain → :inter    (climb 0)   ~ 5G N2
diff layer              → :crossing (climb k = levels to first common ancestor)
no common ancestor      → ArgumentError (members not federated)
```

Worked (hierarchy): Movistar→Orange meets at `exchange-es` → climb 1;
Movistar→MEO meets at `eu-root` → climb 2. Same code, different depth. Every
prior hand-written case is now a depth of this one rule, including depths nobody
wrote yet (a continent layer = climb 3).

`charge_move!` walking this rule reproduces the legacy `dispatch_handover!` σ
counters **exactly** (asserted in `test/LayerTests.jl`) — the generalization is a
provable superset, not a rewrite of the paper's numbers. In the live loop,
`observe_move!` records the crossing climb depth into `SimGlobalState.ho_climb`
(observation only; σ charging stays with the legacy dispatch).

## Connectivity: two graphs per layer (do not conflate)

A layer has **two** graphs, and they are different (PNA "Melding Address Spaces
and the Hierarchy of Layers", l.3082; l.648):

- **Service view (seen from above):** *fully connected* — every member appears
  one hop from every other. This is what a UE/member perceives.
- **Forwarding view (seen from below):** *sparse* — edge nodes multiplexing +
  interior nodes **relaying**, arcs carried by the layer below. Traffic between
  two non-adjacent members relays through the interior; not every pair holds a
  direct lower-layer flow. *"Most networks are not fully connected meshes…
  improve connectivity by relaying"* (l.648).

`Layer.edges` in the code is the **forwarding view** (a sparse relay graph). The
service view is implicit (complete). An edge is **not a physical wire** — it is a
flow provided by the layer below.

### Consequence for the federation cost claim

Both architectures deliver complete *reachability*. The O(K) vs O(K²) difference
is in **configured state**, not the reachability graph:

- **5G:** complete reachability requires **O(K²) configured bilateral** links —
  each operator pair a direct SEPP↔SEPP N32 + IR.21 + agreement, **no relay**
  through a third operator (Roaming Hubs are the trusted-third-party concession
  that admits the mesh doesn't scale — GSMA NG.113 §4.2).
- **RUPA:** complete reachability from **O(K) enrollment** (join by one flow to
  one existing member, RM §2.1.1/2.1.2) + **relay** over the sparse forwarding
  graph. Routing synthesizes the full-mesh service; K² links are never
  configured.

Correct sentence: *same reachability, O(K²) configured mesh vs O(K) enrollment +
relay.* Do **not** state it as "RUPA sparse vs 5G complete" — both are complete
at the service level.

## Addressing (planned, not yet built)

`_address(layer, node) = (layer<<20)|node` today is a **synthetic id**, not
topological. Planned: real **hierarchical topological addresses** whose prefix
reflects position in the aggregation tree, so forwarding-by-aggregate becomes
real longest-prefix matching instead of the current placeholder entries. Not
needed for the σ numbers (constant-based); valuable as an explanation asset and
to make "the aggregate prefix already exists → renumber just adopts it" (ΔS_core
= 0) concrete. To be added when the address-aware visualization is built.

## Files

- `src/Simulation/Layers.jl` — the model + `classify_move` / `charge_move!` /
  `observe_move!` / `export_layer_stack_json`.
- `runs/hierarchy.jl` — the N-level scenario (climb histogram, per-layer table
  sizes, membership axis).
- `runs/layers_viz.jl` — exports `viz/data/layers_{flat,hierarchy}.json`.
- `viz/graph_of_graphs.svg` — the schematic figure (paper-figure candidate).
- `test/LayerTests.jl` — 50 assertions incl. the legacy-equivalence safety net.
