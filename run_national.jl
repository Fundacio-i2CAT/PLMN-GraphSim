#!/usr/bin/env julia
# National-grade mobility evaluation, parametric by country.
#   julia --project run_national.jl spain
#   julia --project run_national.jl usa
#
# Full OpenCellID topology (no subsampling), principled two-tier deployment matching
# the IEEE Access paper: edge UPFs by population geography (Spain 52 provinces /
# USA 817 counties >60k) over 5 centralized PSAs (hierarchical K-means parent map).
# Agent count derived from real demand (population x adoption / scale_factor) and
# placed by municipal population distribution. Each serving-gNB change is a handover,
# classified by level (L1 Xn / L2 N2 UL-CL / L3 N2 PSA-reloc; 6G-RUPA renumber) and
# charged its spec-grounded sigma; core forwarding-state writes tracked separately.

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
import DesJulia6gRupa.Simulation as DSim

const COUNTRY = lowercase(get(ARGS, 1, "spain"))
const SCALE = 1000
const NUM_PSA = 5                 # centralized PSAs (config.toml num_centralized_upfs)
const ADOPTION = 0.82             # mobile_adoption_rate (config.toml)

# (data subdir, mcc csv files, OpenCellID operator net id, #edge UPFs, population)
const PROFILES = Dict(
    "spain" => ("spain", ["214.csv"],            7,   52,  49_442_844),
    "usa"   => ("usa",   ["310.csv","311.csv"], 480, 817, 335_000_000),
)

function build_topology()
    haskey(PROFILES, COUNTRY) || error("unknown country $COUNTRY")
    sub, files, opid, nedge, _pop = PROFILES[COUNTRY]
    base = joinpath(@__DIR__, "data", sub, "opencellid")
    paths = filter(isfile, [joinpath(base, f) for f in files])
    isempty(paths) && error("no OpenCellID data under $base")
    # two_tier: nedge edge UPFs (UL-CL) clustered under NUM_PSA centralized PSAs
    cfg = SimConfig(1, 2, SCALE, 1, 1, 1, :two_tier, NUM_PSA, 1)
    topo = DSim.load_and_deploy_network(paths, opid, nedge, joinpath(@__DIR__, "data", sub), cfg)
    return topo, nedge
end

# Principled agent count: effective mobile users represented at this scale_factor.
national_agents() = ceil(Int, PROFILES[COUNTRY][5] * ADOPTION / SCALE)

function run_scenario(topology, nupf, name, model; n_agents, duration, dt)
    config = SimConfig(1, 2, SCALE, Float64(duration), Float64(duration)-5, 5.0,
                       :two_tier, NUM_PSA, 10.0,
                       MobilityConfig(true, Float64(dt), model))
    s = DSim.init_global_state_for_simulation(topology, config)
    env = ConcurrentSim.Simulation()
    @process DSim.monitor_metrics(env, s, topology, config.scale_factor)
    for uid in 1:n_agents
        @process DSim.user_lifecycle(env, uid, s, topology, eMBB)
    end
    run(env, config.duration)

    xn, n2 = s.sigma_5g_xn, s.sigma_5g_n2
    intra, inter = s.sigma_rupa_intra, s.sigma_rupa_inter
    t5 = xn + n2                             # SSC-1: L1 Xn + L2 N2 (PSA pinned)
    t6 = intra + inter                       # σ_rupa flat 200 at every level
    rate = s.handover_count / n_agents / (duration/3600)
    adv = t5 > 0 ? (1 - t6/t5)*100 : 0.0
    ho = s.handover_count
    pct(x) = ho > 0 ? round(100x/ho, digits=1) : 0.0
    ns = s.anchor_stretch_samples
    d5  = ns > 0 ? s.anchor_dist_5g_sum/ns  : 0.0    # mean 5G hairpin (pinned PSA)
    dop = ns > 0 ? s.anchor_dist_opt_sum/ns : 0.0    # mean optimal (nearest PSA, RUPA)

    println("\n", "="^70)
    println("SCENARIO: $name   [$(uppercase(COUNTRY)), $nupf edge UPFs / $NUM_PSA PSAs]")
    println("  agents=$n_agents duration=$(duration)s dt=$(dt)s")
    println("="^70)
    println("Handovers: $ho  ($(round(rate,digits=1)) HO/user/hr)")
    println("Level mix: L1(Xn)=$(s.ho_l1) ($(pct(s.ho_l1))%)  L2(N2)=$(s.ho_l2) ($(pct(s.ho_l2))%)   [PSA-region crossings=$(s.ho_l3), anchor pinned]")
    println("5G σ: Xn(L1) $(xn)B  N2(L2) $(n2)B  total $(t5)B")
    println("6G σ: flat-renumber $(t6÷200)ev=$(t6)B (σ=200/event, all levels)")
    println("Core writes:  5G=$(s.core_writes_5g)  6G-RUPA=$(s.core_writes_rupa) (ΔS_core=0)")
    println("Anchor path:  5G(pinned)=$(round(d5,digits=1))km  RUPA(optimal)=$(round(dop,digits=1))km  excess=$(round(d5-dop,digits=1))km (SSC-1 hairpin)")
    println("Acct reloc:   5G=$(s.acct_reloc_5g)  6G-RUPA=$(s.acct_reloc_rupa) (SSC-1 intra-PLMN: 0 both; billing orthogonal, granularity equal)")
    println("6G-RUPA σ advantage: $(round(adv,digits=1))% ($t5 vs $t6 B)")
    return (; name, ho, rate, t5, t6, adv,
            l1=s.ho_l1, l2=s.ho_l2, psaX=s.ho_l3,
            cw5=s.core_writes_5g, cw6=s.core_writes_rupa,
            d5, dop)
end

println("Building $(uppercase(COUNTRY)) topology...")
topology, nupf = build_topology()
NAG = national_agents()
println("Topology: $(length(topology.gnb_locations)) gNBs, $(length(topology.upf_locations)) edge UPFs, $NUM_PSA PSAs")
println("Agents: $NAG  (= $(PROFILES[COUNTRY][5]) pop x $ADOPTION adoption / $SCALE scale)")

res = Any[]
push!(res, run_scenario(topology, nupf, "Pedestrian 5km/h (RWP)",
        RandomWaypoint(5.0, 0.0, 2.0);   n_agents=NAG, duration=1200, dt=2))
push!(res, run_scenario(topology, nupf, "Urban 50km/h (RWP)",
        RandomWaypoint(50.0, 0.0, 20.0); n_agents=NAG, duration=1200, dt=2))
push!(res, run_scenario(topology, nupf, "Highway 120km/h (GaussMarkov)",
        GaussMarkov(120.0, 0.85, 5.0);   n_agents=NAG, duration=1200, dt=2))

println("\n", "#"^70)
println("SUMMARY ($(uppercase(COUNTRY)), $nupf edge UPFs / $NUM_PSA PSAs, $NAG agents)")
println("#"^70)
for r in res
    println(rpad(r.name,32), " HO=", r.ho, " rate=", round(r.rate,digits=1),
            "/u/hr  adv=", round(r.adv,digits=1),
            "%  CW:5G=", r.cw5, " 6G=", r.cw6,
            "  stretch:5G=", round(r.d5,digits=1), "km opt=", round(r.dop,digits=1), "km")
end
