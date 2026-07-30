#!/usr/bin/env julia
# Starlink escalation across every country, not just Iberia.
#
#   julia --project main.jl ntn_sweep                       # all country/field targets
#   julia --project main.jl ntn_sweep canada-ised           # one target
#   julia --project main.jl ntn_sweep idx:3 20000 600       # smoke
#
# runs/ntn.jl fixes the terrestrial side to the composed Iberian field. That is the
# wrong control for this question, because how often a user falls off terrestrial
# coverage is a property of the country: Canada, Mexico and the United States have
# far larger gaps than France or Spain. This sweep therefore runs the same
# constellation against each national field in turn.
#
# It also runs the official registries where they exist (FCC ASR, ANFR, ISED)
# alongside the crowdsourced fields, because satellite attachment is driven by
# coverage holes and OpenCellID overstates those by roughly a factor of three.
#
# Agent count is capped so every country costs the same and the reported
# satellite-served fraction stays a per-agent statistic.

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
import DesJulia6gRupa.Simulation as DSim
import DesJulia6gRupa.DataLoading as DL
using Random, CSV, DataFrames

const ONLY = lowercase(get(ARGS, 1, "all"))
const AGENT_CAP = parse(Int, get(ARGS, 2, "50000"))
const DURATION = parse(Int, get(ARGS, 3, "1200"))
const OUTPUT = get(ARGS, 4, joinpath(pkgdir(DesJulia6gRupa), "results", "ntn-sweep.csv"))
const MODEL_ONLY = lowercase(get(ARGS, 5, "all"))
const R_SWEEP = [parse(Float64, x) for x in split(get(ARGS, 6, "5,10,20,30"), ",")]
const HO_SWEEP = [Symbol(lowercase(x)) for x in split(get(ARGS, 7, "xn,n2"), ",")]
const CONSTELLATION = lowercase(get(ARGS, 8, "starlink"))
const SEMANTICS = :reestablish
const SCALE = 1000
const ADOPTION = 0.82
const MIN_ELEV = 25.0
const SEED = 20260728

const TLE_FILES = Dict(
    "starlink" => "tles_starlink_550_sgp.txt",
    "oneweb"   => "tles_oneweb_synth.txt",
    "kuiper"   => "tles_kuiper_synth.txt",
    "telesat"  => "tles_telesat_synth.txt",
)

# country, field, subdir, csvs, operator, mnc, edge UPFs, PSAs, population
const TARGETS = [
    ("spain",    "opencellid", "spain",    ["opencellid/214.csv"], "Movistar", 7,   52,  5, 49_442_844),
    ("portugal", "opencellid", "portugal", ["opencellid/268.csv"], "MEO",      6,   18,  2, 9_855_909),
    ("usa",      "opencellid", "usa",      ["opencellid/310.csv", "opencellid/311.csv"], "Verizon", 480, 817, 5, 335_000_000),
    ("usa",      "fcc-asr",    "usa",      ["asr/310.csv"],        "all-structures", 999, 817, 5, 335_000_000),
    ("france",   "opencellid", "france",   ["opencellid/208.csv"], "Orange",   1,   96,  5, 66_165_815),
    ("france",   "anfr",       "france",   ["anfr/208.csv"],       "Orange",   1,   96,  5, 66_165_815),
    ("canada",   "opencellid", "canada",   ["opencellid/302.csv"], "Telus",    220, 126, 4, 36_991_981),
    ("canada",   "ised",       "canada",   ["ised/302.csv"],       "Telus",    220, 126, 4, 36_991_981),
    ("mexico",   "opencellid", "mexico",   ["opencellid/334.csv"], "Telcel",   20,  445, 5, 125_822_502),
]

const MODELS = [
    ("stationary", "Stationary",                    NoMobility()),
    ("pedestrian", "Pedestrian 5km/h (RWP)",        RandomWaypoint(5.0, 0.0, 2.0)),
    ("highway",    "Highway 120km/h (GaussMarkov)", GaussMarkov(120.0, 0.85, 5.0)),
]

function build(sub, csvs, mnc, nedge, npsa)
    base = joinpath(pkgdir(DesJulia6gRupa), "data", sub)
    paths = filter(isfile, [joinpath(base, f) for f in csvs])
    isempty(paths) && error("no gNB data under $base for $csvs")
    cfg = SimConfig(1, 2, SCALE, 1, 1, 1, :two_tier, npsa, 1)
    return DL.load_and_deploy_network(paths, mnc, nedge, base, cfg)
end

# Only the graph mutates during a run; share the immutable arrays across cases.
fresh(t) = NetworkTopology(t.gnb_locations, t.upf_locations, t.gnb_to_upf_map,
                           t.centralized_upf_locations, t.edge_upf_parent_map,
                           t.municipalities, t.municipality_bins, t.municipality_probs,
                           deepcopy(t.graph), t.gnb_operator, t.psa_operator)

function run_case(base_topology, tle_path, r_terr, model_id, mname, model, ho_sem,
                  n_agents, duration, dt, seed)
    Random.seed!(seed)
    topology = fresh(base_topology)
    config = SimConfig(1, 2, SCALE, Float64(duration), Float64(duration) - 5, 5.0,
                       :two_tier, length(topology.centralized_upf_locations), 10.0,
                       MobilityConfig(true, Float64(dt), model),
                       RoamingConfig(SEMANTICS, 0.0))
    s = DSim.init_global_state_for_simulation(topology, config)
    c = DSim.load_constellation(tle_path; operator_id = 9, min_elevation_deg = MIN_ELEV,
                                r_terr_km = r_terr, handover_semantics = ho_sem,
                                snapshot_interval_sec = 1.0)
    DSim.install_ntn_member!(s, topology, c)
    env = ConcurrentSim.Simulation()
    @process DSim.monitor_metrics(env, s, topology, config.scale_factor)
    for uid in 1:n_agents
        @process DSim.user_lifecycle(env, uid, s, topology, eMBB)
    end
    run(env, config.duration)

    frac = s.ntn_total_ticks > 0 ? s.ntn_serving_ticks / s.ntn_total_ticks * 100 : 0.0
    outage = s.ntn_total_ticks > 0 ? s.ntn_outage_ticks / s.ntn_total_ticks * 100 : 0.0
    cadv = s.sigma_ntn_cross_5g > 0 ? (1 - s.sigma_ntn_cross_rupa / s.sigma_ntn_cross_5g) * 100 : 0.0
    hadv = s.sigma_ntn_ho_5g > 0 ? (1 - s.sigma_ntn_ho_rupa / s.sigma_ntn_ho_5g) * 100 : 0.0
    t5 = s.sigma_5g_xn + s.sigma_5g_n2
    t6 = s.sigma_rupa_intra + s.sigma_rupa_inter
    iadv = t5 > 0 ? (1 - t6 / t5) * 100 : 0.0
    return (; constellation = CONSTELLATION, r_terr_km = r_terr,
            mobility_model = model_id, satellite_ho_semantics = String(ho_sem),
            agents = n_agents, duration_s = duration,
            satellite_served_pct = frac, outage_pct = outage,
            ntn_attach_events = s.ntn_attach_events, ntn_return_events = s.ntn_return_events,
            satellite_handovers = s.ntn_sat_handovers,
            sigma_crossing_5g = s.sigma_ntn_cross_5g, sigma_crossing_rupa = s.sigma_ntn_cross_rupa,
            crossing_advantage_pct = cadv,
            sigma_satellite_ho_5g = s.sigma_ntn_ho_5g, sigma_satellite_ho_rupa = s.sigma_ntn_ho_rupa,
            satellite_ho_advantage_pct = hadv,
            session_breaks_5g = s.ntn_session_breaks_5g,
            terrestrial_advantage_pct = iadv)
end

selected = if ONLY == "all"
    TARGETS
elseif startswith(ONLY, "idx:")
    [TARGETS[parse(Int, split(ONLY, ":")[2])]]
else
    keys = Set(split(ONLY, ","))
    filter(t -> lowercase(t[1]) in keys || "$(lowercase(t[1]))-$(lowercase(t[2]))" in keys, TARGETS)
end
isempty(selected) && error("no target matched '$ONLY'")
models = MODEL_ONLY == "all" ? MODELS : filter(m -> m[1] in Set(split(MODEL_ONLY, ",")), MODELS)
isempty(models) && error("no mobility profile matched '$MODEL_ONLY'")

tle = joinpath(pkgdir(DesJulia6gRupa), "data", "ntn", TLE_FILES[CONSTELLATION])
isfile(tle) || error("no TLE file $tle")

rows = Any[]
t_start = time()
println("ntn_sweep: $(length(selected)) targets x $(length(R_SWEEP)) ranges x " *
        "$(length(models)) profiles x $(length(HO_SWEEP)) semantics -> $OUTPUT")

for (country, field, sub, csvs, oplabel, mnc, nedge, npsa, pop) in selected
    Random.seed!(SEED)
    topo = build(sub, csvs, mnc, nedge, npsa)
    nag = min(AGENT_CAP, ceil(Int, pop * ADOPTION / SCALE))
    println("\n", "="^74)
    println("$country/$field/$oplabel: $(length(topo.gnb_locations)) gNBs, $nag agents " *
            "($(round((time()-t_start)/60, digits=1)) min elapsed)")
    for (ri, r) in enumerate(R_SWEEP), (mi, (mid, mname, model)) in enumerate(models),
        ho in HO_SWEEP
        t0 = time()
        res = run_case(topo, tle, r, mid, mname, model, ho, nag, DURATION, 2,
                       SEED + 100ri + mi)
        push!(rows, merge((; country, field, operator = oplabel, mnc,
                             gnbs = length(topo.gnb_locations)), res))
        println("  r=$(Int(r))km $(rpad(mid,11)) $(rpad(String(ho),3)) " *
                "sat=$(round(res.satellite_served_pct, digits=2))% " *
                "up/down=$(res.ntn_attach_events)/$(res.ntn_return_events) " *
                "satHO=$(res.satellite_handovers) " *
                "cross-adv=$(round(res.crossing_advantage_pct, digits=1))% " *
                "breaks5G=$(res.session_breaks_5g) ($(round((time()-t0)/60, digits=1)) min)")
    end
end

mkpath(dirname(OUTPUT))
CSV.write(OUTPUT, DataFrame(rows))
println("\ndone in $(round((time()-t_start)/60, digits=1)) min -> $OUTPUT")
