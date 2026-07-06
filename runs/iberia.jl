#!/usr/bin/env julia
# Iberia two-country roaming evaluation (§7.4 phase 2).
#   julia --project main.jl iberia                # deployed default (:reestablish)
#   julia --project main.jl iberia ideal_ho       # 5G best-case sensitivity
#   julia --project main.jl iberia reestablish 500 300   # smoke: 500 agents, 300 s
#
# Composes the Spain (Movistar, 52 edge / 5 PSA) and Portugal (MEO, 18 edge / 2 PSA)
# national topologies into one multi-operator field. Agents are placed by the merged
# population distribution (Censos/INE weights, both countries); an agent whose nearest
# gNB flips operator has geometrically crossed the border — the roaming trigger. HR
# pins the anchor in the home country, so the roaming path-stretch (visited edge UPF →
# home PSA) is measured directly, alongside σ_roam, session breaks, and the intra-PLMN
# baseline metrics that must match the standalone national runs.

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
import DesJulia6gRupa.Simulation as DSim
import DesJulia6gRupa.DataLoading as DL

const SEMANTICS = Symbol(lowercase(get(ARGS, 1, "reestablish")))
const AGENT_OVERRIDE = parse(Int, get(ARGS, 2, "0"))   # 0 = full national demand
const DURATION = parse(Int, get(ARGS, 3, "1200"))
const SCALE = 1000
const ADOPTION = 0.82

# (data subdir, gNB csvs, operator net id, #edge, #psa, population) — same values as
# the run_national.jl profiles; keep in sync.
const HOME    = ("spain",    ["opencellid/214.csv"], 7, 52, 5, 49_442_844)
const VISITED = ("portugal", ["opencellid/268.csv"], 6, 18, 2, 9_855_909)

function build_country(sub, files, opid, nedge, npsa)
    base = joinpath(pkgdir(DesJulia6gRupa), "data", sub)
    paths = filter(isfile, [joinpath(base, f) for f in files])
    isempty(paths) && error("no gNB data under $base for $files")
    cfg = SimConfig(1, 2, SCALE, 1, 1, 1, :two_tier, npsa, 1)
    return DL.load_and_deploy_network(paths, opid, nedge, base, cfg)
end

function run_scenario(topology, name, model; n_agents, duration, dt)
    config = SimConfig(1, 2, SCALE, Float64(duration), Float64(duration)-5, 5.0,
                       :two_tier, length(topology.centralized_upf_locations), 10.0,
                       MobilityConfig(true, Float64(dt), model),
                       RoamingConfig(SEMANTICS, 0.0))
    s = DSim.init_global_state_for_simulation(topology, config)
    env = ConcurrentSim.Simulation()
    @process DSim.monitor_metrics(env, s, topology, config.scale_factor)
    for uid in 1:n_agents
        @process DSim.user_lifecycle(env, uid, s, topology, eMBB)
    end
    run(env, config.duration)

    t5 = s.sigma_5g_xn + s.sigma_5g_n2
    t6 = s.sigma_rupa_intra + s.sigma_rupa_inter
    adv = t5 > 0 ? (1 - t6/t5)*100 : 0.0
    radv = s.sigma_roam_5g > 0 ? (1 - s.sigma_roam_rupa/s.sigma_roam_5g)*100 : 0.0
    ns  = s.anchor_stretch_samples
    d5  = ns > 0 ? s.anchor_dist_5g_sum/ns  : 0.0
    dop = ns > 0 ? s.anchor_dist_opt_sum/ns : 0.0
    rns = s.roam_stretch_samples
    rd5 = rns > 0 ? s.roam_dist_5g_sum/rns  : 0.0
    rdo = rns > 0 ? s.roam_dist_opt_sum/rns : 0.0

    println("\n", "="^70)
    println("SCENARIO: $name   [IBERIA: Movistar 52/5 + MEO 18/2, semantics=:$SEMANTICS]")
    println("  agents=$n_agents duration=$(duration)s dt=$(dt)s")
    println("="^70)
    println("Handovers: $(s.handover_count)  (border crossings: $(s.roam_entries))")
    println("Intra-PLMN (must match national runs):")
    println("  L1(Xn)=$(s.ho_l1)  L2(N2)=$(s.ho_l2)  σ adv=$(round(adv,digits=1))%  CW:5G=$(s.core_writes_5g) 6G=$(s.core_writes_rupa)")
    println("  domestic anchor path: 5G=$(round(d5,digits=1))km opt=$(round(dop,digits=1))km excess=$(round(d5-dop,digits=1))km")
    println("Roaming (geometric border, $(SEMANTICS)):")
    println("  σ_roam: 5G=$(s.sigma_roam_5g)B  6G=$(s.sigma_roam_rupa)B  adv=$(round(radv,digits=1))%")
    println("  session breaks at border: 5G=$(s.session_breaks_5g)  [RUPA: 0, make-before-break]")
    println("  acct relocations: 5G=$(s.acct_reloc_5g)  6G=$(s.acct_reloc_rupa)")
    println("  ROAMING path (HR hairpin to home PSA): 5G=$(round(rd5,digits=1))km  RUPA(nearest aggregate)=$(round(rdo,digits=1))km  excess=$(round(rd5-rdo,digits=1))km  [$(rns) samples]")
    return (; name, ho=s.handover_count, entries=s.roam_entries, adv, radv,
            breaks=s.session_breaks_5g, rd5, rdo, rns)
end

println("Building Iberia composed topology (Spain Movistar + Portugal MEO)...")
home = build_country(HOME[1], HOME[2], HOME[3], HOME[4], HOME[5])
visited = build_country(VISITED[1], VISITED[2], VISITED[3], VISITED[4], VISITED[5])
topology = DL.compose_topologies(home, visited)
NAG = AGENT_OVERRIDE > 0 ? AGENT_OVERRIDE : ceil(Int, (HOME[6] + VISITED[6]) * ADOPTION / SCALE)
println("Composed: $(length(topology.gnb_locations)) gNBs, $(length(topology.upf_locations)) edge UPFs, $(length(topology.centralized_upf_locations)) PSAs, $(length(topology.municipalities)) municipalities")
println("Agents: $NAG  (= $(HOME[6]) + $(VISITED[6]) pop x $ADOPTION / $SCALE)")

res = Any[]
push!(res, run_scenario(topology, "Pedestrian 5km/h (RWP)",
        RandomWaypoint(5.0, 0.0, 2.0);   n_agents=NAG, duration=DURATION, dt=2))
push!(res, run_scenario(topology, "Urban 50km/h (RWP)",
        RandomWaypoint(50.0, 0.0, 20.0); n_agents=NAG, duration=DURATION, dt=2))
push!(res, run_scenario(topology, "Highway 120km/h (GaussMarkov)",
        GaussMarkov(120.0, 0.85, 5.0);   n_agents=NAG, duration=DURATION, dt=2))

println("\n", "#"^70)
println("SUMMARY (IBERIA, semantics=:$SEMANTICS, $NAG agents)")
println("#"^70)
for r in res
    println(rpad(r.name,32), " HO=", r.ho, " border=", r.entries,
            "  intra-adv=", round(r.adv,digits=1), "%  roam-adv=", round(r.radv,digits=1),
            "%  breaks=", r.breaks,
            "  roam-stretch:5G=", round(r.rd5,digits=1), "km opt=", round(r.rdo,digits=1), "km")
end
