#!/usr/bin/env julia
# National-grade Spain mobility evaluation.
#
# Uses the FULL 46k-gNB OpenCellID topology with real K-means UPF clustering
# (no subsampling). Persistent mobile eMBB agents move under the (now fixed)
# Random Waypoint / Gauss-Markov models; each serving-gNB change triggers a
# handover that is classified (Xn / N2 for 5G, intra/inter-domain for 6G-RUPA)
# and charged its spec-grounded signaling cost sigma.

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
import DesJulia6gRupa.Simulation as DSim

const DATA_DIR = "/home/sergio/phd/PLMN-GraphSim/data/spain"
const OPERATOR_NET_ID = 7      # OpenCellID operator filter (matches prior runs)
const N_UPFS = 20              # regional 5G core sites (UPF anchors)

function build_topology(n_upfs)
    paths = [joinpath(DATA_DIR, "opencellid", "214.csv")]
    paths = filter(isfile, paths)
    isempty(paths) && error("Spain OpenCellID data not found under $DATA_DIR")
    cfg = SimConfig(1, 2, 1000, 1, 1, 1, :single_tier, 0, 1)  # placeholder for loader
    return DSim.load_and_deploy_network(paths, OPERATOR_NET_ID, n_upfs, DATA_DIR, cfg)
end

function run_scenario(topology, name, model; n_agents, duration, dt)
    config = SimConfig(1, 2, 1000, Float64(duration), Float64(duration)-5, 5.0,
                       :single_tier, 0, 10.0,
                       MobilityConfig(true, Float64(dt), model))

    sim_state = DSim.init_global_state_for_simulation(topology, config)
    env = ConcurrentSim.Simulation()
    @process DSim.monitor_metrics(env, sim_state, topology, config.scale_factor)
    for uid in 1:n_agents
        @process DSim.user_lifecycle(env, uid, sim_state, topology, eMBB)
    end
    run(env, config.duration)

    ho   = sim_state.handover_count
    xn   = sim_state.sigma_5g_xn
    n2   = sim_state.sigma_5g_n2
    intra = sim_state.sigma_rupa_intra
    inter = sim_state.sigma_rupa_inter
    tot5g = xn + n2
    tot6g = intra + inter
    xn_ev = xn ÷ 600
    n2_ev = n2 ÷ 1150
    in_ev = intra ÷ 200
    it_ev = inter ÷ 400

    # handovers per user per hour
    hours = duration / 3600
    ho_rate = ho / n_agents / max(hours, 1e-9)

    println("\n" * "="^70)
    println("SCENARIO: $name")
    println("  agents=$n_agents duration=$(duration)s dt=$(dt)s UPFs=$N_UPFS")
    println("="^70)
    println("Handovers (cell changes): $ho   => $(round(ho_rate,digits=1)) HO/user/hour")
    if tot5g > 0
        println("\n5G signaling (total $tot5g B):")
        println("  Xn (600B):  $xn_ev events = $xn B  ($(round(100xn/tot5g,digits=1))%)")
        println("  N2 (1150B): $n2_ev events = $n2 B  ($(round(100n2/tot5g,digits=1))%)")
        println("\n6G-RUPA signaling (total $tot6g B):")
        println("  intra (200B): $in_ev events = $intra B  ($(round(100intra/max(tot6g,1),digits=1))%)")
        println("  inter (400B): $it_ev events = $inter B  ($(round(100inter/max(tot6g,1),digits=1))%)")
        adv = (1 - tot6g/tot5g) * 100
        println("\n6G-RUPA advantage: $(round(adv,digits=1))% lower signaling ($tot5g vs $tot6g B)")
    else
        println("\n(no handovers recorded)")
    end
    return (; name, ho, ho_rate, tot5g, tot6g, xn_ev, n2_ev, in_ev, it_ev)
end

println("Building full Spain topology (46k gNBs, $N_UPFS UPFs)...")
topology = build_topology(N_UPFS)
println("Topology: $(length(topology.gnb_locations)) gNBs, $(length(topology.upf_locations)) UPFs")

results = Any[]
push!(results, run_scenario(topology, "Pedestrian 5km/h (RWP)",
        RandomWaypoint(5.0, 0.0, 2.0);   n_agents=1000, duration=1200, dt=2))
push!(results, run_scenario(topology, "Urban 50km/h (RWP)",
        RandomWaypoint(50.0, 0.0, 20.0); n_agents=1000, duration=1200, dt=2))
push!(results, run_scenario(topology, "Highway 120km/h (GaussMarkov)",
        GaussMarkov(120.0, 0.85, 5.0);   n_agents=1000, duration=1200, dt=2))

println("\n" * "#"^70)
println("SUMMARY (Spain national, $N_UPFS UPFs)")
println("#"^70)
for r in results
    println(rpad(r.name, 32), " HO=", r.ho,
            "  rate=", round(r.ho_rate, digits=1), "/user/hr",
            "  5G=", r.tot5g, "B  6G=", r.tot6g, "B")
end
