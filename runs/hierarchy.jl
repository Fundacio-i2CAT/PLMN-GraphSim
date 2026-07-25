#!/usr/bin/env julia
# N-level layer hierarchy evaluation (graph-of-graphs): pan-Iberian federation
# with national exchange layers under an EU root.
#   julia --project main.jl hierarchy                        # deployed default (:reestablish)
#   julia --project main.jl hierarchy ideal_ho 2000 600      # semantics, agents, duration
#   julia --project main.jl hierarchy reestablish 0 1200 all # full demand, all mobility
#
# Same 5 real member fields as runs/federation.jl, but the internetwork is no
# longer one flat layer: members 1,3,4 (Spanish operators) federate under
# exchange-es, members 2,5 under exchange-pt, and the two exchanges under
# eu-root — PNA Ch. 10 provider exchange layers, "reflecting corporate
# alliances". The sim classifies every member crossing through the layer DAG
# (Simulation.observe_move!) and reports the climb-depth histogram:
#   climb 1 = crossing resolved at a national exchange (Movistar↔Orange)
#   climb 2 = crossing resolved at the EU root (any ES member ↔ any PT member)
# σ charging is unchanged (RUPA renumber cost is flat in climb by design; the
# equivalence with the flat model is asserted in test/LayerTests.jl) — what the
# hierarchy adds is (a) the depth dimension of crossings, (b) the membership
# axis: bilateral O(K²) vs flat DIF O(K) vs hierarchical enrollment (each
# member joins ONE exchange; exchanges join the root), and (c) per-(node,
# layer) forwarding-table sizes that scale with member count, not user count.

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Statistics
import DesJulia6gRupa.Simulation as DSim
import DesJulia6gRupa.DataLoading as DL

const SEMANTICS = Symbol(lowercase(get(ARGS, 1, "reestablish")))
const AGENT_OVERRIDE = parse(Int, get(ARGS, 2, "0"))   # 0 = full federation demand
const DURATION = parse(Int, get(ARGS, 3, "1200"))
const MOBILITY = lowercase(get(ARGS, 4, "urban"))       # pedestrian|urban|highway|all
const SCALE = 1000
const ADOPTION = 0.82

const MEMBERS = [
    ("Movistar ES", "spain",    ["opencellid/214.csv"], 7, 52, 5),
    ("MEO PT",      "portugal", ["opencellid/268.csv"], 6, 18, 2),
    ("Orange ES",   "spain",    ["opencellid/214.csv"], 3, 52, 5),
    ("Vodafone ES", "spain",    ["opencellid/214.csv"], 1, 52, 5),
    ("Vodafone PT", "portugal", ["opencellid/268.csv"], 1, 18, 2),
]
const COUNTRY_POP = Dict("spain" => 49_442_844, "portugal" => 9_855_909)

const MODELS = [
    ("Pedestrian 5km/h (RWP)",        RandomWaypoint(5.0, 0.0, 2.0)),
    ("Urban 50km/h (RWP)",            RandomWaypoint(50.0, 0.0, 20.0)),
    ("Highway 120km/h (GaussMarkov)", GaussMarkov(120.0, 0.85, 5.0)),
]
const RUN_MODELS = MOBILITY == "all" ? MODELS :
    filter(m -> occursin(MOBILITY, lowercase(m[1])), MODELS)
isempty(RUN_MODELS) && error("unknown mobility '$MOBILITY' (pedestrian|urban|highway|all)")

function build_member(sub, files, opid, nedge, npsa)
    base = joinpath(pkgdir(DesJulia6gRupa), "data", sub)
    paths = filter(isfile, [joinpath(base, f) for f in files])
    isempty(paths) && error("no gNB data under $base for $files")
    cfg = SimConfig(1, 2, SCALE, 1, 1, 1, :two_tier, npsa, 1)
    return DL.load_and_deploy_network(paths, opid, nedge, base, cfg)
end

function build_hierarchy(topology)
    h = DSim.build_layer_stack(topology; internetwork = false)
    m = [DSim.layer_by_name(h, "member-$i").id for i in 1:5]
    ex_es = DSim.add_federation_layer!(h, [m[1], m[3], m[4]]; name = "exchange-es")
    ex_pt = DSim.add_federation_layer!(h, [m[2], m[5]]; name = "exchange-pt")
    DSim.add_federation_layer!(h, [ex_es, ex_pt]; name = "eu-root")
    return h
end

function run_scenario(topology, stack, name, model; n_agents, duration, dt)
    config = SimConfig(1, 2, SCALE, Float64(duration), Float64(duration) - 5, 5.0,
                       :two_tier, length(topology.centralized_upf_locations), 10.0,
                       MobilityConfig(true, Float64(dt), model),
                       RoamingConfig(SEMANTICS, 0.0))
    s = DSim.init_global_state_for_simulation(topology, config)
    s.layer_stack = stack
    env = ConcurrentSim.Simulation()
    @process DSim.monitor_metrics(env, s, topology, config.scale_factor)
    for uid in 1:n_agents
        @process DSim.user_lifecycle(env, uid, s, topology, eMBB)
    end
    run(env, config.duration)

    hours = n_agents * duration / 3600
    t5 = s.sigma_5g_xn + s.sigma_5g_n2
    t6 = s.sigma_rupa_intra + s.sigma_rupa_inter
    println("\n--- $name ---")
    println("  handovers: $(s.handover_count)  (Xn-class $(s.ho_l1) / N2-class $(s.ho_l2))")
    println("  intra-PLMN σ: 5G $(round(t5/1e6, digits=2)) MB vs RUPA $(round(t6/1e6, digits=2)) MB" *
            (t5 > 0 ? "  (adv $(round((1 - t6/t5)*100, digits=1))%)" : ""))
    println("  member crossings: $(s.roam_entries)  ($(round(s.roam_entries/hours, digits=2))/agent/h)")
    println("  crossing σ: 5G $(round(s.sigma_roam_5g/1e6, digits=3)) MB vs RUPA $(round(s.sigma_roam_rupa/1e6, digits=3)) MB" *
            (s.sigma_roam_5g > 0 ? "  (adv $(round((1 - s.sigma_roam_rupa/s.sigma_roam_5g)*100, digits=1))%)" : ""))
    println("  session breaks (5G, scaled): $(s.session_breaks_5g)  |  RUPA: 0")
    println("  crossings by climb depth (graph-of-graphs):")
    labels = ["national exchange (climb 1)", "EU root (climb 2)"]
    for (k, n) in enumerate(s.ho_climb)
        lbl = k <= length(labels) ? labels[k] : "climb $k"
        pct = s.roam_entries > 0 ? round(100n / s.roam_entries, digits=1) : 0.0
        println("    $lbl: $n  ($(pct)%)")
    end
    return s
end

println("=== N-level hierarchy: pan-Iberian federation, semantics=$SEMANTICS ===")
members = [build_member(m[2], m[3], m[4], m[5], m[6]) for m in MEMBERS]
topology = DL.compose_topologies(members)
stack = build_hierarchy(topology)

# Membership axis (analytic): what federating K=5 costs to configure.
K = 5
println("\nMembership state (analytic):")
println("  5G bilateral mesh:      $(K*(K-1)÷2) agreements + N32 relationships")
println("  flat internetwork DIF:  $K enrollments")
println("  hierarchical (this run): $K member enrollments + 2 exchange enrollments at the root")

println("\nPer-layer forwarding state (member-count-scaled, not user-scaled):")
for l in stack.layers
    sizes = [length(g.forwarding_table) for g in l.gupfs]
    println("  $(rpad(l.name, 14)) level $(l.level): $(length(l.gupfs)) GUPFs, " *
            "table sizes $(minimum(sizes))–$(maximum(sizes)) (Σ $(sum(sizes)))")
end

pop = sum(COUNTRY_POP[c] for c in unique(m[2] for m in MEMBERS))
demand = round(Int, pop * ADOPTION / SCALE)
n_agents = AGENT_OVERRIDE > 0 ? AGENT_OVERRIDE : demand
dt = 5.0
println("\nagents=$n_agents  duration=$(DURATION)s  dt=$(dt)s  scale=$SCALE")

for (name, model) in RUN_MODELS
    run_scenario(topology, stack, name, model; n_agents = n_agents,
                 duration = DURATION, dt = dt)
end
