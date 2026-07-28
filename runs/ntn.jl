#!/usr/bin/env julia
# NTN escalation (§7.5.2): satellite constellation as one more federation member.
#   julia --project main.jl ntn                          # defaults below
#   julia --project main.jl ntn ideal_ho                 # 5G best-case sensitivity
#   julia --project main.jl ntn reestablish 2000 600     # smoke: 2000 agents, 600 s
#   julia --project main.jl ntn reestablish 0 1200 starlink 5,10,20,30
#   julia --project main.jl ntn reestablish 2000 600 starlink 5,30 20260728 xn,n2
#   julia --project main.jl ntn reestablish 1200 300 starlink 10 42 n2 /tmp/ntn.csv stationary
#
# Iberia composed field (Movistar + MEO, §7.4) plus a LEO constellation (LEOPath
# TLE sets under data/ntn/, SGP4-propagated; cross-validated in test/NTNTests.jl).
# Trigger: a UE whose nearest terrestrial gNB is farther than r_terr has no
# terrestrial signal and roams to the satellite member. r_terr is SWEPT — real
# macro range is band-dependent (low-band rural ≈20-30 km, mid-band ≈5-10 km) —
# so satellite-attach fraction and crossing rate are reported as functions of the
# coverage assumption; the σ verdict must hold across the sweep. OpenCellID
# undersamples rural sites, so gaps (and satellite roaming) are overestimated:
# disclose next to the results.
#
# While satellite-served the network moves under the UE. Satellite switches sweep
# Xn/N2 handover costs (TS 23.501 Sec. 5.4.14.3) against one RUPA renumber. 5G's NTN integration is per-tier
# anchor special cases (TS 23.501 §5.43.x); RUPA composes the constellation as a
# member via the same compose/enrollment mechanism as §7.5.1.

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
import DesJulia6gRupa.Simulation as DSim
import DesJulia6gRupa.DataLoading as DL
using Random
using CSV
using DataFrames

const SEMANTICS = Symbol(lowercase(get(ARGS, 1, "reestablish")))
const AGENT_OVERRIDE = parse(Int, get(ARGS, 2, "0"))
const DURATION = parse(Int, get(ARGS, 3, "1200"))
const CONSTELLATION = lowercase(get(ARGS, 4, "starlink"))
const R_SWEEP = [parse(Float64, x) for x in split(get(ARGS, 5, "5,10,20,30"), ",")]
const SEED = parse(Int, get(ARGS, 6, "20260728"))
const HO_SWEEP = [Symbol(lowercase(x)) for x in split(get(ARGS, 7, "xn,n2"), ",")]
const OUTPUT = get(ARGS, 8, joinpath(pkgdir(DesJulia6gRupa), "results", "ntn-scenarios.csv"))
const MODEL_SWEEP = Set(lowercase.(split(get(ARGS, 9, "stationary,pedestrian,highway"), ",")))
const SCALE = 1000
const ADOPTION = 0.82
const MIN_ELEV = 25.0

const TLE_FILES = Dict(
    "starlink" => "tles_starlink_550_sgp.txt",
    "oneweb"   => "tles_oneweb_synth.txt",
    "kuiper"   => "tles_kuiper_synth.txt",
    "telesat"  => "tles_telesat_synth.txt",
)

const HOME    = ("spain",    ["opencellid/214.csv"], 7, 52, 5, 49_442_844)
const VISITED = ("portugal", ["opencellid/268.csv"], 6, 18, 2, 9_855_909)

function build_country(sub, files, opid, nedge, npsa)
    base = joinpath(pkgdir(DesJulia6gRupa), "data", sub)
    paths = filter(isfile, [joinpath(base, f) for f in files])
    isempty(paths) && error("no gNB data under $base for $files")
    cfg = SimConfig(1, 2, SCALE, 1, 1, 1, :two_tier, npsa, 1)
    return DL.load_and_deploy_network(paths, opid, nedge, base, cfg)
end

# Only the graph is mutable during a run. Share immutable topology arrays so all
# sweep cases reuse one nearest-gNB spatial index instead of retaining one per copy.
function topology_for_run(t)
    return NetworkTopology(t.gnb_locations, t.upf_locations, t.gnb_to_upf_map,
                           t.centralized_upf_locations, t.edge_upf_parent_map,
                           t.municipalities, t.municipality_bins, t.municipality_probs,
                           deepcopy(t.graph), t.gnb_operator, t.psa_operator)
end

function run_scenario(base_topology, tle_path, r_terr, model_id, name, model, ho_semantics;
                      n_agents, duration, dt, seed)
    Random.seed!(seed)
    topology = topology_for_run(base_topology)
    config = SimConfig(1, 2, SCALE, Float64(duration), Float64(duration)-5, 5.0,
                       :two_tier, length(topology.centralized_upf_locations), 10.0,
                       MobilityConfig(true, Float64(dt), model),
                       RoamingConfig(SEMANTICS, 0.0))
    s = DSim.init_global_state_for_simulation(topology, config)
    c = DSim.load_constellation(tle_path; operator_id = 9,
                                min_elevation_deg = MIN_ELEV, r_terr_km = r_terr,
                                handover_semantics = ho_semantics,
                                snapshot_interval_sec = 1.0)
    DSim.install_ntn_member!(s, topology, c)
    env = ConcurrentSim.Simulation()
    @process DSim.monitor_metrics(env, s, topology, config.scale_factor)
    for uid in 1:n_agents
        @process DSim.user_lifecycle(env, uid, s, topology, eMBB)
    end
    run(env, config.duration)

    frac = s.ntn_total_ticks > 0 ? s.ntn_serving_ticks / s.ntn_total_ticks * 100 : 0.0
    outage_frac = s.ntn_total_ticks > 0 ? s.ntn_outage_ticks / s.ntn_total_ticks * 100 : 0.0
    cadv = s.sigma_ntn_cross_5g > 0 ?
        (1 - s.sigma_ntn_cross_rupa / s.sigma_ntn_cross_5g) * 100 : 0.0
    hadv = s.sigma_ntn_ho_5g > 0 ?
        (1 - s.sigma_ntn_ho_rupa / s.sigma_ntn_ho_5g) * 100 : 0.0
    t5 = s.sigma_5g_xn + s.sigma_5g_n2
    t6 = s.sigma_rupa_intra + s.sigma_rupa_inter
    iadv = t5 > 0 ? (1 - t6/t5) * 100 : 0.0
    sat_hos_per_visit = s.ntn_attach_events > 0 ?
        s.ntn_sat_handovers / s.ntn_attach_events : 0.0
    seconds_per_sat_ho = s.ntn_sat_handovers > 0 ?
        s.ntn_serving_ticks * dt / s.ntn_sat_handovers : 0.0

    println("\n  [r_terr=$(r_terr)km  $name  sat-HO=:$ho_semantics]")
    println("    satellite-served: $(round(frac, digits=2))% of agent-ticks" *
            "   outage: $(round(outage_frac, digits=3))%" *
            "   crossings: $(s.ntn_attach_events)↑ $(s.ntn_return_events)↓" *
            "   sat-HOs (network moved): $(s.ntn_sat_handovers)")
    println("    σ crossing: 5G=$(s.sigma_ntn_cross_5g)B 6G=$(s.sigma_ntn_cross_rupa)B" *
            " adv=$(round(cadv, digits=1))%   σ sat-HO: 5G=$(s.sigma_ntn_ho_5g)B" *
            " 6G=$(s.sigma_ntn_ho_rupa)B adv=$(round(hadv, digits=1))%")
    println("    breaks at crossings: 5G=$(s.ntn_session_breaks_5g)  [RUPA: 0]" *
            "   terrestrial intra σ adv=$(round(iadv, digits=1))% (must match §6)")
    return (; constellation = CONSTELLATION,
            border_semantics = String(SEMANTICS),
            satellite_ho_semantics = String(ho_semantics),
            topology_seed = SEED, seed, agents = n_agents, duration_s = duration,
            update_interval_s = dt, min_elevation_deg = MIN_ELEV,
            r_terr_km = r_terr, mobility_model_id = model_id, mobility_model = name,
            satellite_served_pct = frac, outage_pct = outage_frac,
            ntn_attach_events = s.ntn_attach_events,
            ntn_return_events = s.ntn_return_events,
            satellite_handovers = s.ntn_sat_handovers,
            satellite_handovers_per_visit = sat_hos_per_visit,
            seconds_per_satellite_handover = seconds_per_sat_ho,
            sigma_crossing_5g = s.sigma_ntn_cross_5g,
            sigma_crossing_rupa = s.sigma_ntn_cross_rupa,
            crossing_advantage_pct = cadv,
            sigma_satellite_ho_5g = s.sigma_ntn_ho_5g,
            sigma_satellite_ho_rupa = s.sigma_ntn_ho_rupa,
            satellite_ho_advantage_pct = hadv,
            session_breaks_5g = s.ntn_session_breaks_5g,
            terrestrial_advantage_pct = iadv,
            classified_crossing_climbs = sum(s.ho_climb; init = 0))
end

tle_path = joinpath(pkgdir(DesJulia6gRupa), "data", "ntn", TLE_FILES[CONSTELLATION])
isfile(tle_path) || error("no TLE file $tle_path")

println("Building Iberia composed topology (Movistar + MEO) + $CONSTELLATION member...")
Random.seed!(SEED)
home = build_country(HOME[1], HOME[2], HOME[3], HOME[4], HOME[5])
visited = build_country(VISITED[1], VISITED[2], VISITED[3], VISITED[4], VISITED[5])
topology = DL.compose_topologies(home, visited)
NAG = AGENT_OVERRIDE > 0 ? AGENT_OVERRIDE :
    ceil(Int, (HOME[6] + VISITED[6]) * ADOPTION / SCALE)
println("Composed: $(length(topology.gnb_locations)) gNBs; agents=$NAG; " *
        "semantics=:$SEMANTICS; r_terr sweep=$(R_SWEEP) km")

const MODELS = [
    ("stationary", "Stationary",                       NoMobility()),
    ("pedestrian", "Pedestrian 5km/h (RWP)",           RandomWaypoint(5.0, 0.0, 2.0)),
    ("highway",    "Highway 120km/h (GaussMarkov)",    GaussMarkov(120.0, 0.85, 5.0)),
]

results = Any[]
for (ri, r_terr) in enumerate(R_SWEEP), (mi, (model_id, mname, model)) in enumerate(MODELS),
    ho_semantics in HO_SWEEP
    model_id in MODEL_SWEEP || continue
    case_seed = SEED + 100 * ri + mi
    push!(results, run_scenario(topology, tle_path, r_terr, model_id, mname, model, ho_semantics;
                                n_agents = NAG, duration = DURATION, dt = 2,
                                seed = case_seed))
end

println("\n", "#"^78)
println("NTN SWEEP SUMMARY ($CONSTELLATION, semantics=:$SEMANTICS, $NAG agents)")
println("#"^78)
println(rpad("r_terr", 8), rpad("model", 30), rpad("HO", 5), rpad("sat%", 7),
        rpad("out%", 7), rpad("up/down", 12), rpad("satHO", 8),
        rpad("cross-adv", 10), rpad("satHO-adv", 10), "breaks")
for r in results
    println(rpad(r.r_terr_km, 8), rpad(r.mobility_model, 30),
            rpad(r.satellite_ho_semantics, 5),
            rpad(round(r.satellite_served_pct, digits=2), 7),
            rpad(round(r.outage_pct, digits=3), 7),
            rpad(string(r.ntn_attach_events, "/", r.ntn_return_events), 12),
            rpad(r.satellite_handovers, 8),
            rpad(string(round(r.crossing_advantage_pct, digits=1), "%"), 10),
            rpad(string(round(r.satellite_ho_advantage_pct, digits=1), "%"), 10),
            r.session_breaks_5g)
end

mkpath(dirname(OUTPUT))
CSV.write(OUTPUT, DataFrame(results))
println("\nWrote reproducible NTN results: $OUTPUT")
