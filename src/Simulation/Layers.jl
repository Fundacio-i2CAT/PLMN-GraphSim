# Graph-of-graphs layer model (recursive internetworking).
#
# A federation is a DAG of layers; each layer is one graph whose vertices are
# GUPF instances. A physical node participating in k layers hosts k GUPF
# instances, each with its own forwarding table — recursion happens at border
# nodes, whose "interior" side goes down a layer (PNA Ch. 8). An upper layer
# federates the layers listed in `floats_over`; membership is one enrollment
# per member (O(K)), and the layer hierarchy is a DAG, not a tree: a member
# can enroll in several exchange layers (PNA Ch. 10 provider exchange layers).
#
# Handover classification falls out of the recursion: a move renumbers upward
# through the DAG until it reaches a layer whose aggregate is unchanged. The
# climb depth is the event class — depth 0 intra/inter within a member layer,
# depth ≥1 a member crossing through the first common federation layer. This
# generalizes the flat operator-tag model (exactly 2 implicit levels) to N
# layers over M sublayers, and reproduces its σ counters exactly (equivalence
# asserted in test/LayerTests.jl).
#
# Terminology is 6G-RUPA's: GUPF (not "IPC process"), layer (not "DIF").

using ..Types

"""
One GUPF instance: the participation of a physical node in one layer. The same
node participating in k layers hosts k GUPF instances with independent
forwarding tables (scoped to their layer).
"""
struct GUPF
    layer_id::Int
    node_id::Int
    address::UInt32
    forwarding_table::Vector{ForwardingEntry6GRUPA}
    kind::Symbol   # :edge | :psa | :border | :member (generic base-layer node)
end

"""
One layer: a graph over GUPF instances. `level` 0 = member (base) layer;
federation layers sit at `max(level of lowers) + 1`. `border_node` is the
physical node that represents this layer in an upper layer it enrolls into.
"""
mutable struct Layer
    id::Int
    name::String
    level::Int
    gupfs::Vector{GUPF}
    edges::Vector{Tuple{Int,Int}}      # indices into `gupfs`
    node_to_gupf::Dict{Int,Int}        # physical node id -> index into `gupfs`
    border_node::Int
end

"""
The layer DAG. `floats_over[u]` lists the layers federated by upper layer `u`;
`parents[l]` is the inverse. `member_of` maps an operator tag to its member
layer id (attachment resolution). `node_locations` is shared across layers —
physical nodes exist once, GUPF instances per layer.
"""
struct LayerStack
    layers::Vector{Layer}
    floats_over::Dict{Int,Vector{Int}}
    parents::Dict{Int,Vector{Int}}
    member_of::Dict{Int,Int}
    node_locations::Dict{Int,GeoPoint}
end

"UE attachment: the member layer it is enrolled in + the edge-domain aggregate."
struct Attachment
    layer_id::Int
    domain_id::Int
end

layer_by_name(stack::LayerStack, name::String) =
    stack.layers[findfirst(l -> l.name == name, stack.layers)]

"All GUPF instances a physical node hosts, across every layer."
gupfs_at_node(stack::LayerStack, node_id::Int) =
    [l.gupfs[l.node_to_gupf[node_id]] for l in stack.layers if haskey(l.node_to_gupf, node_id)]

"Index into `layer.gupfs` of the instance at a physical node."
gupf_index_at(layer::Layer, node_id::Int) = layer.node_to_gupf[node_id]

_address(layer_id::Int, node_id::Int) =
    UInt32((UInt32(layer_id) << 20) | (UInt32(node_id) & 0x000FFFFF))

function _push_gupf!(layer::Layer, node_id::Int,
                     table::Vector{ForwardingEntry6GRUPA}, kind::Symbol)
    push!(layer.gupfs, GUPF(layer.id, node_id, _address(layer.id, node_id), table, kind))
    layer.node_to_gupf[node_id] = length(layer.gupfs)
    return layer.gupfs[end]
end

function _new_layer!(stack::LayerStack, name::String, level::Int)
    id = length(stack.layers) + 1
    layer = Layer(id, name, level, GUPF[], Tuple{Int,Int}[], Dict{Int,Int}(), 0)
    push!(stack.layers, layer)
    stack.floats_over[id] = Int[]
    stack.parents[id] = Int[]
    return layer
end

"""
    build_layer_stack(t::NetworkTopology; internetwork = true) -> LayerStack

Build the layer stack for a composed multi-operator topology: one member layer
per operator tag (GUPFs at that member's edge UPFs and PSAs), plus — unless
`internetwork = false` — one federation layer over all members with a border
GUPF per member PSA. Physical node ids: edge UPF i -> i, PSA j -> E + j (E =
number of edge UPFs), matching the composed index space.

With `internetwork = false` the members are left unfederated so callers can
build an explicit hierarchy with `add_federation_layer!` (exchange layers, a
root over exchanges, …).
"""
function build_layer_stack(t::NetworkTopology; internetwork::Bool = true,
                           internetwork_name::String = "internetwork")
    E = length(t.upf_locations)
    P = length(t.centralized_upf_locations)

    # Operator of an edge UPF: from any gNB it serves; fallback to its PSA tag.
    edge_op = zeros(Int, E)
    for (g, u) in enumerate(t.gnb_to_upf_map)
        edge_op[u] == 0 && (edge_op[u] = g <= length(t.gnb_operator) ? t.gnb_operator[g] : 1)
    end
    for i in 1:E
        if edge_op[i] == 0
            edge_op[i] = !isempty(t.edge_upf_parent_map) ?
                         t.psa_operator[t.edge_upf_parent_map[i]] : 1
        end
    end

    ops = sort(unique(vcat(edge_op, t.psa_operator)))
    locations = Dict{Int,GeoPoint}()
    for i in 1:E
        locations[i] = t.upf_locations[i]
    end
    for j in 1:P
        locations[E + j] = t.centralized_upf_locations[j]
    end

    stack = LayerStack(Layer[], Dict{Int,Vector{Int}}(), Dict{Int,Vector{Int}}(),
                       Dict{Int,Int}(), locations)

    gnbs_of_edge = [Int[] for _ in 1:E]
    for (g, u) in enumerate(t.gnb_to_upf_map)
        push!(gnbs_of_edge[u], g)
    end

    for op in ops
        layer = _new_layer!(stack, "member-$op", 0)
        stack.member_of[op] = layer.id
        member_edges = [i for i in 1:E if edge_op[i] == op]
        member_psas = [j for j in 1:P if t.psa_operator[j] == op]

        # Edge GUPFs: one entry per served gNB + a default route up to the PSA.
        for i in member_edges
            table = [ForwardingEntry6GRUPA(UInt32(g), 0xFFFFFF00, Int32(1))
                     for g in gnbs_of_edge[i]]
            push!(table, ForwardingEntry6GRUPA(UInt32(0), 0x00000000, Int32(2)))
            _push_gupf!(layer, i, table, :edge)
        end
        # PSA GUPFs: one entry per child edge domain + a default border uplink.
        for j in member_psas
            children = !isempty(t.edge_upf_parent_map) ?
                       [i for i in member_edges if t.edge_upf_parent_map[i] == j] : Int[]
            table = [ForwardingEntry6GRUPA(UInt32(i), 0xFFFFFF00, Int32(1))
                     for i in children]
            push!(table, ForwardingEntry6GRUPA(UInt32(0), 0x00000000, Int32(2)))
            node = E + j
            _push_gupf!(layer, node, table, :psa)
            layer.border_node == 0 && (layer.border_node = node)
            for i in children
                push!(layer.edges, (layer.node_to_gupf[i], layer.node_to_gupf[node]))
            end
        end
        # Multi-PSA members: chain the PSAs so the member graph is connected.
        for k in 2:length(member_psas)
            push!(layer.edges, (layer.node_to_gupf[E + member_psas[k - 1]],
                                layer.node_to_gupf[E + member_psas[k]]))
        end
        layer.border_node == 0 && !isempty(member_edges) &&
            (layer.border_node = member_edges[1])
    end

    if internetwork
        member_ids = [l.id for l in stack.layers]
        inet = _new_layer!(stack, internetwork_name, 1)
        for op in ops
            member = stack.layers[stack.member_of[op]]
            for j in 1:P
                t.psa_operator[j] == op || continue
                # Border GUPF: forwards by member aggregate — one entry per
                # member, independent of user count (the ΔS claim).
                table = [ForwardingEntry6GRUPA(UInt32(o) << 24, 0xFF000000,
                                               Int32(k))
                         for (k, o) in enumerate(ops)]
                _push_gupf!(inet, E + j, table, :border)
            end
        end
        inet.border_node = isempty(inet.gupfs) ? 0 : inet.gupfs[1].node_id
        # Sparse connected adjacency (a chain suffices: a layer routes/relays,
        # unlike the 5G SEPP mesh which needs the complete bilateral graph).
        for k in 2:length(inet.gupfs)
            push!(inet.edges, (k - 1, k))
        end
        stack.floats_over[inet.id] = member_ids
        for m in member_ids
            push!(stack.parents[m], inet.id)
        end
    end

    return stack
end

"""
    add_member_layer!(stack, node_ids; name, locations = nothing) -> layer id

A new base (level-0) member layer with one GUPF per physical node — e.g. an
NTN constellation, one GUPF per satellite. Not enrolled anywhere until
`enroll!` is called (enrollment is the membership primitive).
"""
function add_member_layer!(stack::LayerStack, node_ids::Vector{Int};
                           name::String,
                           locations::Union{Nothing,Vector{GeoPoint}} = nothing)
    layer = _new_layer!(stack, name, 0)
    for (k, node) in enumerate(node_ids)
        table = [ForwardingEntry6GRUPA(_address(layer.id, node), 0xFFFFFF00, Int32(1))]
        _push_gupf!(layer, node, table, :member)
        locations !== nothing && (stack.node_locations[node] = locations[k])
    end
    for k in 2:length(node_ids)
        push!(layer.edges, (k - 1, k))
    end
    layer.border_node = isempty(node_ids) ? 0 : node_ids[1]
    return layer.id
end

"""
    add_federation_layer!(stack, lower_ids; name) -> layer id

A federation layer over `lower_ids` (members or other federation layers — the
DAG recursion). One border GUPF per lower layer, at that layer's border node,
forwarding by lower-layer aggregate.
"""
function add_federation_layer!(stack::LayerStack, lower_ids::Vector{Int};
                               name::String)
    layer = _new_layer!(stack, name,
                        maximum(stack.layers[l].level for l in lower_ids) + 1)
    for (k, lid) in enumerate(lower_ids)
        lower = stack.layers[lid]
        table = [ForwardingEntry6GRUPA(UInt32(o) << 24, 0xFF000000, Int32(k2))
                 for (k2, o) in enumerate(lower_ids)]
        _push_gupf!(layer, lower.border_node, table, :border)
    end
    for k in 2:length(layer.gupfs)
        push!(layer.edges, (k - 1, k))
    end
    layer.border_node = isempty(layer.gupfs) ? 0 : layer.gupfs[1].node_id
    stack.floats_over[layer.id] = copy(lower_ids)
    for lid in lower_ids
        push!(stack.parents[lid], layer.id)
    end
    return layer.id
end

"""
    enroll!(stack, upper_id, lower_id)

Enroll a layer into an existing federation layer: one new border GUPF for the
newcomer and an aggregate entry advertised into the existing border GUPFs.
This is configured membership state — O(1) per join, O(K) total — not
per-user forwarding state; contrast the 5G bilateral mesh (O(K²)).
"""
function enroll!(stack::LayerStack, upper_id::Int, lower_id::Int)
    upper = stack.layers[upper_id]
    lower = stack.layers[lower_id]
    push!(stack.floats_over[upper_id], lower_id)
    push!(stack.parents[lower_id], upper_id)

    # Advertise the new member's aggregate to existing border GUPFs.
    iface = Int32(length(stack.floats_over[upper_id]))
    agg = ForwardingEntry6GRUPA(_address(lower_id, lower.border_node), 0xFF000000, iface)
    for g in upper.gupfs
        push!(g.forwarding_table, agg)
    end
    # One border GUPF for the newcomer, reaching every member aggregate.
    table = [ForwardingEntry6GRUPA(UInt32(k) << 24, 0xFF000000, Int32(k))
             for k in 1:length(stack.floats_over[upper_id])]
    _push_gupf!(upper, lower.border_node, table, :border)
    isempty(upper.gupfs) || length(upper.gupfs) < 2 ||
        push!(upper.edges, (length(upper.gupfs) - 1, length(upper.gupfs)))
    return stack
end

"UE attachment from a composed gNB index: (member layer of its operator, edge domain)."
function attachment_of(stack::LayerStack, t::NetworkTopology, gnb_index::Int)
    op = (gnb_index >= 1 && gnb_index <= length(t.gnb_operator)) ?
         t.gnb_operator[gnb_index] : 1
    return Attachment(stack.member_of[op], t.gnb_to_upf_map[gnb_index])
end

# Ancestor ids reachable in exactly `k` up-steps (BFS frontier per level).
function _ancestor_frontiers(stack::LayerStack, layer_id::Int, kmax::Int)
    frontiers = Vector{Set{Int}}(undef, kmax + 1)
    frontiers[1] = Set([layer_id])
    for k in 1:kmax
        frontiers[k + 1] = Set{Int}()
        for l in frontiers[k], p in stack.parents[l]
            push!(frontiers[k + 1], p)
        end
    end
    return frontiers
end

"""
    classify_move(stack, old, new) -> (class, climb, common_layer)

The recursion-native handover classifier. Same layer: `:intra` (same domain)
or `:inter` (different domain), climb 0. Different member layers: `:crossing`,
with `climb` = number of levels up the DAG to the first layer common to both
members' ancestries, and `common_layer` that layer's id. No common ancestor:
the members are not federated — `ArgumentError`.
"""
function classify_move(stack::LayerStack, old::Attachment, new::Attachment)
    if old.layer_id == new.layer_id
        cls = old.domain_id == new.domain_id ? :intra : :inter
        return (class = cls, climb = 0, common_layer = old.layer_id)
    end
    kmax = length(stack.layers)
    fo = _ancestor_frontiers(stack, old.layer_id, kmax)
    fn = _ancestor_frontiers(stack, new.layer_id, kmax)
    reach_old, reach_new = Set([old.layer_id]), Set([new.layer_id])
    for k in 1:kmax
        union!(reach_old, fo[k + 1])
        union!(reach_new, fn[k + 1])
        common = intersect(reach_old, reach_new)
        isempty(common) || return (class = :crossing, climb = k,
                                   common_layer = minimum(common))
    end
    throw(ArgumentError(
        "no common federation layer over layers $(old.layer_id) and $(new.layer_id) — members are not federated"))
end

"""
    charge_move!(sim_state, stack, old, new; num_sessions = 1) -> classification

Charge one physical move through the layer classifier, updating the SAME σ /
event counters as the legacy flat dispatch (equivalence asserted in tests):

  :intra    → 5G Xn 600 B          | RUPA renumber 200 B
  :inter    → 5G N2 1150 B         | RUPA renumber 200 B (flat by architecture)
  :crossing → 5G roam 3250 B (:reestablish, + session breaks + accounting
              relocation) or 1300 B (:ideal_ho) | RUPA entry 450 B, 0 breaks

The climb depth is recorded by the caller if needed; σ_RUPA is deliberately
flat in climb — enrollment + renumber cost the same whether the first common
layer is one or three levels up. ΔS_core = 0: no forwarding table is touched.
"""
function charge_move!(sim_state::SimGlobalState, stack::LayerStack,
                      old::Attachment, new::Attachment; num_sessions::Int = 1)
    r = classify_move(stack, old, new)
    scaled = Int64(num_sessions) * Int64(sim_state.config.scale_factor)
    sim_state.handover_count += 1
    if r.class == :intra
        sim_state.sigma_5g_xn += Int64(600)
        sim_state.sigma_rupa_intra += Int64(200)
        sim_state.ho_l1 += 1
    elseif r.class == :inter
        sim_state.sigma_5g_n2 += Int64(1150)
        sim_state.sigma_rupa_inter += Int64(200)
        sim_state.ho_l2 += 1
    else
        sim_state.roam_entries += 1
        sim_state.ho_l2 += 1
        if sim_state.config.roaming.border_semantics == :ideal_ho
            sim_state.sigma_roam_5g += SIGMA_ROAM_5G_IDEAL_HO
        else
            sim_state.sigma_roam_5g += SIGMA_ROAM_5G_REESTABLISH
            sim_state.session_breaks_5g += scaled
            sim_state.acct_reloc_5g += scaled
        end
        sim_state.sigma_roam_rupa += SIGMA_ROAM_RUPA_ENTRY
    end
    # 5G core churn: per-session state rewritten at the serving UPF (O(n));
    # RUPA ΔS_core stays 0 at every climb depth.
    sim_state.core_writes_5g += scaled
    return r
end

"""
    observe_move!(sim_state, topology, old_gnb, new_gnb) -> classification | nothing

Layer-DAG observation hook for the live sim loop: when `sim_state.layer_stack`
holds a `LayerStack`, classify the physical move through the DAG and record the
crossing climb depth in `sim_state.ho_climb` (histogram: index k = crossings
resolved k levels above the member layers). Returns the classification, or
`nothing` when no stack is installed.

Observation only: σ charging stays with the legacy `dispatch_handover!` — this
adds the recursion-depth dimension the flat operator-tag model cannot express
(climb 1 = crossing via a direct exchange layer, climb 2 = via the root, …).
"""
function observe_move!(sim_state::SimGlobalState, topology::NetworkTopology,
                       old_gnb::Int, new_gnb::Int)
    stack = sim_state.layer_stack
    stack === nothing && return nothing
    r = classify_move(stack::LayerStack,
                      attachment_of(stack, topology, old_gnb),
                      attachment_of(stack, topology, new_gnb))
    if r.class == :crossing
        while length(sim_state.ho_climb) < r.climb
            push!(sim_state.ho_climb, Int64(0))
        end
        sim_state.ho_climb[r.climb] += 1
    end
    return r
end

"""
    export_layer_stack_json(stack, path)

Snapshot the whole stack (layers, GUPFs with per-instance table sizes, edges,
DAG) for the layer visualization.
"""
function export_layer_stack_json(stack::LayerStack, path::String)
    layers = map(stack.layers) do l
        Dict(
            "id" => l.id, "name" => l.name, "level" => l.level,
            "border_node" => l.border_node,
            "gupfs" => [Dict(
                "node_id" => g.node_id,
                "layer_id" => g.layer_id,
                "address" => g.address,
                "table_size" => length(g.forwarding_table),
                "kind" => string(g.kind),
                "lat" => haskey(stack.node_locations, g.node_id) ?
                         stack.node_locations[g.node_id].lat : 0.0,
                "lon" => haskey(stack.node_locations, g.node_id) ?
                         stack.node_locations[g.node_id].lon : 0.0,
            ) for g in l.gupfs],
            "edges" => [[a, b] for (a, b) in l.edges],
        )
    end
    doc = Dict("layers" => layers,
               "floats_over" => Dict(string(k) => v
                                     for (k, v) in stack.floats_over if !isempty(v)))
    open(path, "w") do io
        write(io, JSON.json(doc))
    end
    return path
end
