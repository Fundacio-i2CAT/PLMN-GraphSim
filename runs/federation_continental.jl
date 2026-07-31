#!/usr/bin/env julia
# Continental federations: two independent "network of networks", one per continent.
#   julia --project main.jl federation_continental europe
#   julia --project main.jl federation_continental north_america ideal_ho
#   julia --project main.jl federation_continental europe reestablish 3000 300 urban
#
# runs/federation.jl composes five members drawn from two adjacent countries, three
# of them Spanish operators, so most of its K sweep varies operator rather than
# country. That understates what a federation is for. Here each federation spans a
# contiguous continental landmass and adds a country before it adds a second
# operator within one, so growing K widens the geography rather than the operator
# list:
#
#   europe        Movistar ES -> MEO PT -> Orange FR -> Vodafone ES -> NOS PT -> SFR FR
#   north_america Verizon US  -> Telus CA -> Telcel MX -> AT&T US -> Rogers CA -> Movistar MX
#
# Contiguity matters because an inter-member crossing has to be reachable on the
# ground: Iberia and France share borders, as do the three North American members.
# The two federations differ by an order of magnitude in area and in coverage gap,
# which is the point: per-crossing cost should not care.

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
import DesJulia6gRupa.Simulation as DSim
import DesJulia6gRupa.DataLoading as DL

const FEDERATION = lowercase(get(ARGS, 1, "europe"))    # europe|north_america
const SEMANTICS = Symbol(lowercase(get(ARGS, 2, "reestablish")))
const AGENT_OVERRIDE = parse(Int, get(ARGS, 3, "0"))    # 0 = full federation demand
const DURATION = parse(Int, get(ARGS, 4, "1200"))
const MOBILITY = lowercase(get(ARGS, 5, "urban"))       # pedestrian|urban|highway|all
const OUTPUT = get(ARGS, 6, joinpath(pkgdir(DesJulia6gRupa), "results",
                                     "federation-$(FEDERATION).csv"))
const SCALE = 1000
const ADOPTION = 0.82

# (label, data subdir, gNB csvs, operator net id, #edge UPFs, #PSAs)
# Edge and PSA counts follow the same admin-unit rule used everywhere else, so a
# member keeps its national partition when it joins a federation.
const FEDERATIONS = Dict(
    "europe" => [
        ("Movistar ES", "spain",    ["opencellid/214.csv"], 7,  52, 5),
        ("MEO PT",      "portugal", ["opencellid/268.csv"], 6,  18, 2),
        ("Orange FR",   "france",   ["opencellid/208.csv"], 1,  96, 5),
        ("Vodafone ES", "spain",    ["opencellid/214.csv"], 1,  52, 5),
        ("NOS PT",      "portugal", ["opencellid/268.csv"], 3,  18, 2),
        ("SFR FR",      "france",   ["opencellid/208.csv"], 10, 96, 5),
    ],
    "north_america" => [
        ("Verizon US",  "usa",    ["opencellid/310.csv", "opencellid/311.csv"], 480, 817, 5),
        ("Telus CA",    "canada", ["opencellid/302.csv"], 220, 126, 4),
        ("Telcel MX",   "mexico", ["opencellid/334.csv"], 20,  445, 5),
        ("AT&T US",     "usa",    ["opencellid/310.csv", "opencellid/311.csv"], 410, 817, 5),
        ("Rogers CA",   "canada", ["opencellid/302.csv"], 720, 126, 4),
        ("Movistar MX", "mexico", ["opencellid/334.csv"], 3,   445, 5),
    ],
)
haskey(FEDERATIONS, FEDERATION) || error("unknown federation '$FEDERATION' (europe|north_america)")
const MEMBERS = FEDERATIONS[FEDERATION]

const COUNTRY_POP = Dict("spain" => 49_442_844, "portugal" => 9_855_909,
                         "france" => 66_165_815, "usa" => 335_000_000,
                         "canada" => 36_991_981, "mexico" => 125_822_502)

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
println("FEDERATION SWEEP SUMMARY ($FEDERATION, semantics=:$SEMANTICS, mobility=$MOBILITY)")
println("#"^70)
println(rpad("K",3), rpad("model",30), rpad("bilat",6), rpad("enrol",6),
        rpad("cross/ag/h",11), rpad("roam-adv",9), rpad("breaks",10), "excess-km")
for r in results
    println(rpad(r.K,3), rpad(r.model,30), rpad(r.K*(r.K-1)÷2,6), rpad(r.K,6),
            rpad(round(r.xrate,digits=2),11), rpad(string(round(r.radv,digits=1),"%"),9),
            rpad(r.breaks,10), round(r.rd5-r.rdo,digits=1))
end

mkpath(dirname(OUTPUT))
open(OUTPUT, "w") do io
    println(io, "federation,members,K,bilateral_agreements,rupa_enrollments,semantics," *
                "mobility_model,handovers,roam_entries,crossings_per_agent_hr," *
                "intra_sigma_adv_pct,roam_sigma_adv_pct,session_breaks_5g," *
                "roam_path_5g_km,roam_path_opt_km,roam_excess_km")
    for r in results
        println(io, join((FEDERATION, join((m[1] for m in MEMBERS[1:r.K]), "|"), r.K,
                          r.K*(r.K-1)÷2, r.K, String(SEMANTICS), r.model, r.ho, r.entries,
                          round(r.xrate, digits=4), round(r.adv, digits=3),
                          round(r.radv, digits=3), r.breaks,
                          round(r.rd5, digits=3), round(r.rdo, digits=3),
                          round(r.rd5 - r.rdo, digits=3)), ","))
    end
end
println("\nwrote $OUTPUT")
