#!/usr/bin/env julia
# Deployment-pattern sweep: vary UPF count (centralized core -> distributed edge)
# on the full real topology, fixed mobility (Gauss-Markov 50 km/h). Tests whether
# the 6G-RUPA advantage is robust to deployment density, and how the Xn/N2 mix
# shifts as anchor regions shrink. Multiple seeds for confidence.
#
#   julia --project run_deployment_sweep.jl spain
#   julia --project run_deployment_sweep.jl usa

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Random
import DesJulia6gRupa.Simulation as DSim

const COUNTRY = lowercase(get(ARGS, 1, "spain"))
const PROFILES = Dict(
    "spain" => ("spain", ["214.csv"],            7),
    "usa"   => ("usa",   ["310.csv","311.csv"], 480),
)
const UPF_COUNTS = [5, 20, 50, 100, 200]
const SEEDS = [1, 2]
const NAG = 600
const DUR = 600
const DT = 2
const SPEED = 50.0

sub, files, opid = PROFILES[COUNTRY]
base = joinpath(@__DIR__, "data", sub)
paths = filter(isfile, [joinpath(base, "opencellid", f) for f in files])

println("Deployment-pattern sweep [$(uppercase(COUNTRY))]  GM $(SPEED)km/h, $NAG agents, $(DUR)s, seeds=$(length(SEEDS))")
println(rpad("UPFs",6), rpad("HO(mean)",10), rpad("N2%(mean)",10),
        rpad("5G MB/hr",10), rpad("6G MB/hr",10), "adv%(mean±sd)")

results = []
for nupf in UPF_COUNTS
    cfg0 = SimConfig(1, 2, 1000, 1, 1, 1, :single_tier, 0, 1)
    topo = DSim.load_and_deploy_network(paths, opid, nupf, base, cfg0)
    advs = Float64[]; hos = Int[]; n2fracs = Float64[]; t5s = Int[]; t6s = Int[]
    for sd in SEEDS
        Random.seed!(sd)
        config = SimConfig(1, 2, 1000, Float64(DUR), Float64(DUR)-5, 5.0,
                           :single_tier, 0, 10.0,
                           MobilityConfig(true, Float64(DT), GaussMarkov(SPEED, 0.85, 5.0)))
        s = DSim.init_global_state_for_simulation(topo, config)
        env = ConcurrentSim.Simulation()
        @process DSim.monitor_metrics(env, s, topo, config.scale_factor)
        for uid in 1:NAG
            @process DSim.user_lifecycle(env, uid, s, topo, eMBB)
        end
        run(env, config.duration)
        t5 = s.sigma_5g_xn + s.sigma_5g_n2
        t6 = s.sigma_rupa_intra + s.sigma_rupa_inter
        push!(advs, t5>0 ? (1-t6/t5)*100 : 0.0)
        push!(hos, s.handover_count)
        push!(n2fracs, s.handover_count>0 ? (s.sigma_5g_n2÷1150)/s.handover_count : 0.0)
        push!(t5s, t5); push!(t6s, t6)
    end
    mean(x) = sum(x)/length(x)
    sd(x) = length(x)>1 ? sqrt(sum((xi-mean(x))^2 for xi in x)/(length(x)-1)) : 0.0
    hrs = DUR/3600
    mb5 = mean(t5s)/1e6/hrs   # MB per hour (whole population)
    mb6 = mean(t6s)/1e6/hrs
    push!(results, (; nupf, ho=mean(hos), n2=100mean(n2fracs), mb5, mb6,
                      adv=mean(advs), advsd=sd(advs)))
    println(rpad(string(nupf),6), rpad(string(round(Int,mean(hos))),10),
            rpad(string(round(100mean(n2fracs),digits=2)),10),
            rpad(string(round(mb5,digits=2)),10), rpad(string(round(mb6,digits=2)),10),
            "$(round(mean(advs),digits=1)) ± $(round(sd(advs),digits=2))")
    flush(stdout)
end

# persist
open(joinpath(@__DIR__, "results", "deployment_sweep_$(COUNTRY).csv"), "w") do io
    println(io, "upfs,ho_mean,n2_pct,mb5_per_hr,mb6_per_hr,adv_mean,adv_sd")
    for r in results
        println(io, "$(r.nupf),$(round(r.ho,digits=1)),$(round(r.n2,digits=3)),",
                    "$(round(r.mb5,digits=3)),$(round(r.mb6,digits=3)),",
                    "$(round(r.adv,digits=2)),$(round(r.advsd,digits=3))")
    end
end
println("\nsaved results/deployment_sweep_$(COUNTRY).csv")

println("\nInterpretation:")
println("- If adv% stays ~65-67% across all UPF counts => advantage robust to deployment pattern.")
println("- N2% should rise with UPF count (smaller anchor regions => more boundary crossings).")
println("- Absolute load (MB/hr) rises with UPF count for 5G faster than 6G (N2 costs 1150 vs inter 400).")
