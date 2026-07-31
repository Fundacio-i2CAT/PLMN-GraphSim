#!/usr/bin/env julia
# National sweep across every country, field and operator, emitting one CSV row
# per (target, mobility profile).
#
#   julia --project main.jl national_sweep                  # every target
#   julia --project main.jl national_sweep france,canada    # country subset
#   julia --project main.jl national_sweep all 2000 300     # smoke: 2000 agents, 300 s
#
# Targets are (country, field, operator) triples. "field" is the base-station
# source: the crowdsourced OpenCellID field for every country, plus the official
# registry where one exists (FCC ASR for the USA, ANFR BNIR for France, ISED
# spectrum licence site data for Canada). Operator ids are the real MNCs, so the
# same operator can be compared across the two fields.
#
# Deployment parameters follow runs/national.jl: edge UPFs are second-level
# administrative units above 50k inhabitants, PSAs are round(pop / 10M) clamped
# to [2, 5], agent count is population x adoption / scale factor.

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
import DesJulia6gRupa.Simulation as DSim
using Printf

const ONLY = lowercase(get(ARGS, 1, "all"))
const AGENT_OVERRIDE = parse(Int, get(ARGS, 2, "0"))
const DURATION = parse(Int, get(ARGS, 3, "1200"))
const OUTPUT = get(ARGS, 4, joinpath(pkgdir(DesJulia6gRupa), "results", "national-sweep.csv"))
# Optional mobility-profile filter, so one (target, profile) pair can run as its own
# process. With 27 targets and 3 profiles the full matrix shards into 81 independent
# jobs, which is what keeps the wall time near the longest single job rather than the
# sum of all of them.
const MODEL_ONLY = lowercase(get(ARGS, 5, "all"))
const SCALE = 1000
const ADOPTION = 0.82

# country, field, subdir, csvs, operator label, MNC, edge UPFs, PSAs, population
const TARGETS = [
    ("spain",    "opencellid", "spain",    ["opencellid/214.csv"], "Movistar",   7,   52, 5, 49_442_844),
    ("spain",    "opencellid", "spain",    ["opencellid/214.csv"], "Orange",     3,   52, 5, 49_442_844),
    ("spain",    "opencellid", "spain",    ["opencellid/214.csv"], "Vodafone",   1,   52, 5, 49_442_844),
    ("portugal", "opencellid", "portugal", ["opencellid/268.csv"], "MEO",        6,   18, 2, 9_855_909),
    ("portugal", "opencellid", "portugal", ["opencellid/268.csv"], "Vodafone",   1,   18, 2, 9_855_909),
    ("portugal", "opencellid", "portugal", ["opencellid/268.csv"], "NOS",        3,   18, 2, 9_855_909),
    ("usa",      "opencellid", "usa",      ["opencellid/310.csv", "opencellid/311.csv"], "Verizon",  480, 817, 5, 335_000_000),
    ("usa",      "opencellid", "usa",      ["opencellid/310.csv", "opencellid/311.csv"], "AT&T",     410, 817, 5, 335_000_000),
    ("usa",      "opencellid", "usa",      ["opencellid/310.csv", "opencellid/311.csv"], "T-Mobile", 260, 817, 5, 335_000_000),
    ("usa",      "fcc-asr",    "usa",      ["asr/310.csv"],        "all-structures", 999, 817, 5, 335_000_000),
    ("france",   "opencellid", "france",   ["opencellid/208.csv"], "Orange",     1,   96, 5, 66_165_815),
    ("france",   "opencellid", "france",   ["opencellid/208.csv"], "SFR",        10,  96, 5, 66_165_815),
    ("france",   "opencellid", "france",   ["opencellid/208.csv"], "Free",       15,  96, 5, 66_165_815),
    ("france",   "opencellid", "france",   ["opencellid/208.csv"], "Bouygues",   20,  96, 5, 66_165_815),
    ("france",   "anfr",       "france",   ["anfr/208.csv"],       "Orange",     1,   96, 5, 66_165_815),
    ("france",   "anfr",       "france",   ["anfr/208.csv"],       "SFR",        10,  96, 5, 66_165_815),
    ("france",   "anfr",       "france",   ["anfr/208.csv"],       "Free",       15,  96, 5, 66_165_815),
    ("france",   "anfr",       "france",   ["anfr/208.csv"],       "Bouygues",   20,  96, 5, 66_165_815),
    ("canada",   "opencellid", "canada",   ["opencellid/302.csv"], "Telus",      220, 126, 4, 36_991_981),
    ("canada",   "opencellid", "canada",   ["opencellid/302.csv"], "Rogers",     720, 126, 4, 36_991_981),
    ("canada",   "opencellid", "canada",   ["opencellid/302.csv"], "Bell",       610, 126, 4, 36_991_981),
    ("canada",   "ised",       "canada",   ["ised/302.csv"],       "Telus",      220, 126, 4, 36_991_981),
    ("canada",   "ised",       "canada",   ["ised/302.csv"],       "Rogers",     720, 126, 4, 36_991_981),
    ("canada",   "ised",       "canada",   ["ised/302.csv"],       "Bell",       610, 126, 4, 36_991_981),
    ("mexico",   "opencellid", "mexico",   ["opencellid/334.csv"], "Telcel",     20,  445, 5, 125_822_502),
    ("mexico",   "opencellid", "mexico",   ["opencellid/334.csv"], "Movistar",   3,   445, 5, 125_822_502),
    ("mexico",   "opencellid", "mexico",   ["opencellid/334.csv"], "AT&T",       50,  445, 5, 125_822_502),
]

const MODELS = [
    ("pedestrian", 5.0,   () -> RandomWaypoint(5.0, 0.0, 2.0)),
    ("urban",      50.0,  () -> RandomWaypoint(50.0, 0.0, 20.0)),
    ("highway",    120.0, () -> GaussMarkov(120.0, 0.85, 5.0)),
]

const HEADER = "country,field,operator,mnc,gnbs,edge_upf,psa,agents,mobility_model,speed_kmh," *
               "handovers,ho_per_user_hr,l1_xn_pct,l2_n2_pct,psa_region_crossings," *
               "sigma_5g_bytes,sigma_6grupa_bytes,sigma_advantage_pct," *
               "core_writes_5g,core_writes_6grupa,anchor_dist_5g_km,anchor_dist_opt_km,stretch_excess_km"

function build(sub, csvs, mnc, nedge, npsa)
    base = joinpath(pkgdir(DesJulia6gRupa), "data", sub)
    paths = filter(isfile, [joinpath(base, f) for f in csvs])
    isempty(paths) && error("no gNB data under $base for $csvs")
    cfg = SimConfig(1, 2, SCALE, 1, 1, 1, :two_tier, npsa, 1)
    return DSim.load_and_deploy_network(paths, mnc, nedge, base, cfg)
end

function run_one(topology, npsa, model, n_agents, duration, dt)
    config = SimConfig(1, 2, SCALE, Float64(duration), Float64(duration) - 5, 5.0,
                       :two_tier, npsa, 10.0,
                       MobilityConfig(true, Float64(dt), model),
                       RoamingConfig(:reestablish, 0.0))
    s = DSim.init_global_state_for_simulation(topology, config)
    env = ConcurrentSim.Simulation()
    @process DSim.monitor_metrics(env, s, topology, config.scale_factor)
    for uid in 1:n_agents
        @process DSim.user_lifecycle(env, uid, s, topology, eMBB)
    end
    run(env, config.duration)
    return s
end

selected = if ONLY == "all"
    TARGETS
elseif startswith(ONLY, "idx:")            # 1-based target index, e.g. idx:7
    [TARGETS[parse(Int, split(ONLY, ":")[2])]]
else
    keys = Set(split(ONLY, ","))
    filter(t -> lowercase(t[1]) in keys ||
                "$(lowercase(t[1]))-$(lowercase(t[2]))" in keys, TARGETS)
end
isempty(selected) && error("no targets matched '$ONLY'")

models = MODEL_ONLY == "all" ? MODELS :
    filter(m -> m[1] in Set(split(MODEL_ONLY, ",")), MODELS)
isempty(models) && error("no mobility profile matched '$MODEL_ONLY'")

mkpath(dirname(OUTPUT))
isfile(OUTPUT) || open(io -> println(io, HEADER), OUTPUT, "w")

println("national_sweep: $(length(selected)) targets x $(length(models)) profiles -> $OUTPUT")
t_start = time()

for (i, (country, field, sub, csvs, oplabel, mnc, nedge, npsa, pop)) in enumerate(selected)
    tag = "$country/$field/$oplabel"
    println("\n", "="^72)
    println("[$i/$(length(selected))] $tag  ($(round((time()-t_start)/60, digits=1)) min elapsed)")
    topo = build(sub, csvs, mnc, nedge, npsa)
    ngnb = length(topo.gnb_locations)
    nag = AGENT_OVERRIDE > 0 ? AGENT_OVERRIDE : ceil(Int, pop * ADOPTION / SCALE)
    println("  gNBs=$ngnb edge=$nedge psa=$npsa agents=$nag duration=$(DURATION)s")

    for (mname, speed, mk) in models
        t0 = time()
        s = run_one(topo, npsa, mk(), nag, DURATION, 2)
        ho = s.handover_count
        t5 = s.sigma_5g_xn + s.sigma_5g_n2
        t6 = s.sigma_rupa_intra + s.sigma_rupa_inter
        adv = t5 > 0 ? (1 - t6 / t5) * 100 : 0.0
        rate = ho / nag / (DURATION / 3600)
        pct(x) = ho > 0 ? 100x / ho : 0.0
        ns = s.anchor_stretch_samples
        d5 = ns > 0 ? s.anchor_dist_5g_sum / ns : 0.0
        dop = ns > 0 ? s.anchor_dist_opt_sum / ns : 0.0
        open(OUTPUT, "a") do io
            @printf(io, "%s,%s,%s,%d,%d,%d,%d,%d,%s,%.0f,%d,%.3f,%.2f,%.2f,%d,%d,%d,%.2f,%d,%d,%.2f,%.2f,%.2f\n",
                    country, field, oplabel, mnc, ngnb, nedge, npsa, nag, mname, speed,
                    ho, rate, pct(s.ho_l1), pct(s.ho_l2), s.ho_l3,
                    t5, t6, adv, s.core_writes_5g, s.core_writes_rupa, d5, dop, d5 - dop)
        end
        @printf("  %-11s HO=%-10d rate=%6.1f/u/hr  adv=%5.2f%%  CW5G=%-12d CW6G=%d  (%.1f min)\n",
                mname, ho, rate, adv, s.core_writes_5g, s.core_writes_rupa, (time() - t0) / 60)
    end
end

println("\ndone in $(round((time()-t_start)/60, digits=1)) min -> $OUTPUT")
