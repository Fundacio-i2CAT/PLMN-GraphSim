#!/usr/bin/env julia
# Anchor-count sensitivity: how many session anchors (PSAs) does a country need,
# and what does the choice actually change?
#
#   julia --project main.jl anchor_sweep                 # spain + usa, 2..40 anchors
#   julia --project main.jl anchor_sweep spain 2,5,10,20 # one country, chosen counts
#   julia --project main.jl anchor_sweep all 2,5 3000 300  # smoke
#
# Operators do not publish anchor counts, and no figure is citable from either the
# 3GPP or the GSMA corpus, so every scenario elsewhere in this repo fixes the count
# by a rule that is dominated by its own clamp: round(pop / 10M) bounded to [2, 5]
# gives 5 for Spain and 5 for the United States despite a 6.8x population gap.
#
# That is defensible only if the reported quantities are insensitive to it. This run
# tests exactly that. sigma and the core-write columns should not move with the
# anchor count, because both are set by the edge-UPF partition; rho should fall
# monotonically as anchors are added, because a denser anchor set puts one nearer
# the user. Anything else is a finding.

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
import DesJulia6gRupa.Simulation as DSim
using Printf

const ONLY = lowercase(get(ARGS, 1, "all"))
const PSA_LIST = [parse(Int, x) for x in split(get(ARGS, 2, "2,5,10,20,40"), ",")]
const AGENT_OVERRIDE = parse(Int, get(ARGS, 3, "0"))
const DURATION = parse(Int, get(ARGS, 4, "1200"))
const OUTPUT = get(ARGS, 5, joinpath(pkgdir(DesJulia6gRupa), "results", "anchor-sweep.csv"))
const SCALE = 1000
const ADOPTION = 0.82

# country, subdir, csvs, operator, mnc, edge UPFs, population
const TARGETS = [
    ("spain", "spain", ["opencellid/214.csv"], "Movistar", 7, 52, 49_442_844),
    ("usa",   "usa",   ["opencellid/310.csv", "opencellid/311.csv"], "Verizon", 480, 817, 335_000_000),
]

const MODELS = [
    ("pedestrian", () -> RandomWaypoint(5.0, 0.0, 2.0)),
    ("highway",    () -> GaussMarkov(120.0, 0.85, 5.0)),
]

const HEADER = "country,operator,gnbs,edge_upf,psa,agents,mobility_model,handovers," *
               "l2_n2_pct,psa_region_crossings,sigma_5g_bytes,sigma_6grupa_bytes," *
               "sigma_advantage_pct,core_writes_5g,core_writes_6grupa," *
               "anchor_dist_5g_km,anchor_dist_opt_km,stretch_excess_km"

function build(sub, csvs, mnc, nedge, npsa)
    base = joinpath(pkgdir(DesJulia6gRupa), "data", sub)
    paths = filter(isfile, [joinpath(base, f) for f in csvs])
    isempty(paths) && error("no gNB data under $base")
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

selected = ONLY == "all" ? TARGETS : filter(t -> lowercase(t[1]) in Set(split(ONLY, ",")), TARGETS)
isempty(selected) && error("no target matched '$ONLY'")

mkpath(dirname(OUTPUT))
isfile(OUTPUT) || open(io -> println(io, HEADER), OUTPUT, "w")
println("anchor_sweep: $(length(selected)) countries x $(length(PSA_LIST)) anchor counts " *
        "x $(length(MODELS)) profiles -> $OUTPUT")
t0 = time()

for (country, sub, csvs, oplabel, mnc, nedge, pop) in selected
    nag = AGENT_OVERRIDE > 0 ? AGENT_OVERRIDE : ceil(Int, pop * ADOPTION / SCALE)
    for npsa in PSA_LIST
        # The anchor set is re-clustered for each count, so this is a genuine
        # redeployment rather than a relabelling of the same anchors.
        topo = build(sub, csvs, mnc, nedge, npsa)
        ngnb = length(topo.gnb_locations)
        for (mname, mk) in MODELS
            t = time()
            s = run_one(topo, npsa, mk(), nag, DURATION, 2)
            ho = s.handover_count
            t5 = s.sigma_5g_xn + s.sigma_5g_n2
            t6 = s.sigma_rupa_intra + s.sigma_rupa_inter
            adv = t5 > 0 ? (1 - t6 / t5) * 100 : 0.0
            pct(x) = ho > 0 ? 100x / ho : 0.0
            ns = s.anchor_stretch_samples
            d5 = ns > 0 ? s.anchor_dist_5g_sum / ns : 0.0
            dop = ns > 0 ? s.anchor_dist_opt_sum / ns : 0.0
            open(OUTPUT, "a") do io
                @printf(io, "%s,%s,%d,%d,%d,%d,%s,%d,%.2f,%d,%d,%d,%.3f,%d,%d,%.3f,%.3f,%.3f\n",
                        country, oplabel, ngnb, nedge, npsa, nag, mname, ho,
                        pct(s.ho_l2), s.ho_l3, t5, t6, adv,
                        s.core_writes_5g, s.core_writes_rupa, d5, dop, d5 - dop)
            end
            @printf("  %-6s psa=%-3d %-11s adv=%6.3f%%  CW6G=%d  rho=%6.3f km  psaX=%-6d (%.1f min)\n",
                    country, npsa, mname, adv, s.core_writes_rupa, d5 - dop,
                    s.ho_l3, (time() - t) / 60)
        end
    end
end

println("\ndone in $(round((time()-t0)/60, digits=1)) min -> $OUTPUT")
