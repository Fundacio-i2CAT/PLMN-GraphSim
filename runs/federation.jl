#!/usr/bin/env julia
# Multi-operator federation evaluation (§7.5.1): pan-Iberian "network of networks".
#   julia --project main.jl federation                       # deployed default (:reestablish)
#   julia --project main.jl federation ideal_ho              # 5G best-case sensitivity
#   julia --project main.jl federation reestablish 2000 600  # smoke: 2000 agents, 600 s
#   julia --project main.jl federation reestablish 0 1200 all  # full demand, all mobility
#
# K real operator fields (existing OpenCellID data, no new downloads) composed into
# one shared topology, K swept 2..5. Member order keeps K=2 == the Iberia §7.4
# baseline (Movistar + MEO). In the federation vision an agent attaches to whichever
# member's coverage is best, so member fields OVERLAP and inter-operator crossings
# become routine events — the per-crossing cost decides viability:
#   5G:   every crossing = bilateral-roaming machinery (σ ≈3250 B re-establish /
#         ≈1300 B idealized HO) + session break; agreements form an O(K(K-1)/2)
#         bilateral mesh (GSMA NG.113 §4.2 Model 1; Models 2.3/3/4 add Group SEPPs,
#         aggregators and Roaming Hubs precisely to compress that mesh via trusted
#         third parties).
#   RUPA: every crossing = renumber into the shared internetwork DIF (200 B; 450 B
#         first entry), zero breaks; membership = one enrollment per member, O(K).
# The sim measures per-crossing σ and continuity staying flat in K on real fields;
# the agreement-mesh growth is analytic and printed alongside.

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
import DesJulia6gRupa.Simulation as DSim
import DesJulia6gRupa.DataLoading as DL

const SEMANTICS = Symbol(lowercase(get(ARGS, 1, "reestablish")))
const AGENT_OVERRIDE = parse(Int, get(ARGS, 2, "0"))   # 0 = full federation demand
const DURATION = parse(Int, get(ARGS, 3, "1200"))
const MOBILITY = lowercase(get(ARGS, 4, "urban"))       # pedestrian|urban|highway|all
const SCALE = 1000
const ADOPTION = 0.82

# (label, data subdir, gNB csvs, operator net id, #edge, #psa)
# Edge/PSA counts follow the admin-unit principle per country (Spain 52/5, PT 18/2)
# regardless of operator. K=2 prefix == run_iberia.jl members.
const MEMBERS = [
    ("Movistar ES", "spain",    ["opencellid/214.csv"], 7, 52, 5),
    ("MEO PT",      "portugal", ["opencellid/268.csv"], 6, 18, 2),
    ("Orange ES",   "spain",    ["opencellid/214.csv"], 3, 52, 5),
    ("Vodafone ES", "spain",    ["opencellid/214.csv"], 1, 52, 5),
    ("Vodafone PT", "portugal", ["opencellid/268.csv"], 1, 18, 2),
]
const COUNTRY_POP = Dict("spain" => 49_442_844, "portugal" => 9_855_909)

const MODELS = [
    ("Pedestrian 5km/h (RWP)",       RandomWaypoint(5.0, 0.0, 2.0)),
    ("Urban 50km/h (RWP)",           RandomWaypoint(50.0, 0.0, 20.0)),
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

function run_scenario(topology, name, model, K; n_agents, duration, dt)
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
    rns = s.roam_stretch_samples
    rd5 = rns > 0 ? s.roam_dist_5g_sum/rns  : 0.0
    rdo = rns > 0 ? s.roam_dist_opt_sum/rns : 0.0
    # Crossings per agent per hour: the federation-viability rate.
    xrate = s.roam_entries / n_agents / (duration/3600)

    println("\n  [$name]  HO=$(s.handover_count)  crossings=$(s.roam_entries) " *
            "($(round(xrate, digits=2))/agent/h)")
    println("    intra σ adv=$(round(adv,digits=1))%   roam σ adv=$(round(radv,digits=1))%" *
            "   (5G=$(s.sigma_roam_5g)B 6G=$(s.sigma_roam_rupa)B)")
    println("    breaks: 5G=$(s.session_breaks_5g)  RUPA=0" *
            "   roam-path: 5G=$(round(rd5,digits=1))km opt=$(round(rdo,digits=1))km" *
            " excess=$(round(rd5-rdo,digits=1))km [$rns samples]")
    return (; K, model=name, ho=s.handover_count, entries=s.roam_entries, xrate,
            adv, radv, breaks=s.session_breaks_5g, rd5, rdo)
end

println("Building member fields once (reused across K)...")
fields = [build_member(m[2], m[3], m[4], m[5], m[6]) for m in MEMBERS]
for (m, f) in zip(MEMBERS, fields)
    println("  $(rpad(m[1],14)) $(length(f.gnb_locations)) gNBs, " *
            "$(length(f.upf_locations)) edge, $(length(f.centralized_upf_locations)) PSA")
end

results = Any[]
for K in 2:length(MEMBERS)
    topo = DL.compose_topologies(fields[1:K])
    countries = unique(m[2] for m in MEMBERS[1:K])
    pop = sum(COUNTRY_POP[c] for c in countries)
    nag = AGENT_OVERRIDE > 0 ? AGENT_OVERRIDE : ceil(Int, pop * ADOPTION / SCALE)
    bilaterals = K*(K-1) ÷ 2
    println("\n", "="^70)
    println("K=$K  [", join((m[1] for m in MEMBERS[1:K]), " + "), "]")
    println("  $(length(topo.gnb_locations)) gNBs, $(length(topo.upf_locations)) edge, " *
            "$(length(topo.centralized_upf_locations)) PSAs, " *
            "$(length(topo.municipalities)) municipalities, agents=$nag")
    println("  agreements: 5G bilateral mesh=$bilaterals (O(K²))  " *
            "RUPA enrollments=$K (O(K))  semantics=:$SEMANTICS")
    println("="^70)
    for (mname, model) in RUN_MODELS
        push!(results, run_scenario(topo, mname, model, K;
                                    n_agents=nag, duration=DURATION, dt=2))
    end
end

println("\n", "#"^70)
println("FEDERATION SWEEP SUMMARY (semantics=:$SEMANTICS, mobility=$MOBILITY)")
println("#"^70)
println(rpad("K",3), rpad("model",30), rpad("bilat",6), rpad("enrol",6),
        rpad("cross/ag/h",11), rpad("roam-adv",9), rpad("breaks",10), "excess-km")
for r in results
    println(rpad(r.K,3), rpad(r.model,30), rpad(r.K*(r.K-1)÷2,6), rpad(r.K,6),
            rpad(round(r.xrate,digits=2),11), rpad(string(round(r.radv,digits=1),"%"),9),
            rpad(r.breaks,10), round(r.rd5-r.rdo,digits=1))
end
