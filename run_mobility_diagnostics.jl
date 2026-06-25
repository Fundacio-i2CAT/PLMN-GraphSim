#!/usr/bin/env julia
# Mobility diagnostics: controlled checks that the national results make sense.
#
#  1. CONTROLLED speed sweep with ONE model (Gauss-Markov), same params, varying
#     only speed. If handover rate is geometric it should be ~linear in speed,
#     i.e. HO per km of path travelled should be ~CONSTANT across speeds.
#  2. Compare measured HO/km against the Poisson-Voronoi prediction (4/pi)*sqrt(λ).
#  3. Report N2 fraction vs the sqrt(N_upf/N_gnb) estimate.
#  4. Decompose the advantage to show it is set by the per-event constants given
#     the handover mix (not an emergent simulation output).

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
import DesJulia6gRupa.Simulation as DSim

const N_UPFS = 20
const DUR = 1200
const DT = 2
const NAG = 1000

paths = filter(isfile, [joinpath(@__DIR__, "data", "spain", "opencellid", "214.csv")])
cfg0 = SimConfig(1, 2, 1000, 1, 1, 1, :single_tier, 0, 1)
topo = DSim.load_and_deploy_network(paths, 7, N_UPFS, joinpath(@__DIR__, "data", "spain"), cfg0)
ngnb = length(topo.gnb_locations)

# Spain land area approx (km^2) for density.
const AREA_KM2 = 505_000.0
λ = ngnb / AREA_KM2                       # gNB per km^2
geom_per_km = (4/π) * sqrt(λ)             # expected straight-line crossings/km
n2_est = sqrt(N_UPFS / ngnb)              # rough fraction of handovers that cross a UPF

println("Topology: $ngnb gNBs, $N_UPFS UPFs")
println("gNB density λ = $(round(λ,digits=4))/km^2  =>  geometric crossings ≈ $(round(geom_per_km,digits=3)) HO/km (straight line)")
println("N2 fraction estimate sqrt(N_upf/N_gnb) = $(round(100n2_est,digits=2))%\n")

function run_speed(v)
    model = GaussMarkov(Float64(v), 0.85, 5.0)   # same model+params, only speed varies
    config = SimConfig(1, 2, 1000, Float64(DUR), Float64(DUR)-5, 5.0,
                       :single_tier, 0, 10.0, MobilityConfig(true, Float64(DT), model))
    s = DSim.init_global_state_for_simulation(topo, config)
    env = ConcurrentSim.Simulation()
    @process DSim.monitor_metrics(env, s, topo, config.scale_factor)
    for uid in 1:NAG
        @process DSim.user_lifecycle(env, uid, s, topo, eMBB)
    end
    run(env, config.duration)

    ho = s.handover_count
    n2ev = s.sigma_5g_n2 ÷ 1150
    xnev = s.sigma_5g_xn ÷ 600
    path_km_per_agent = v * DUR / 3600          # GM moves at constant speed v
    ho_per_km = (ho / NAG) / path_km_per_agent
    n2_frac = ho > 0 ? n2ev / ho : 0.0
    return (; v, ho, ho_per_km, n2_frac, xnev, n2ev,
            t5 = s.sigma_5g_xn + s.sigma_5g_n2,
            t6 = s.sigma_rupa_intra + s.sigma_rupa_inter)
end

println(rpad("speed",8), rpad("HO",9), rpad("HO/user/hr",12), rpad("HO/km_path",12),
        rpad("N2%",8), "adv%")
rows = []
for v in (5, 20, 50, 80, 120)
    r = run_speed(v)
    rate = r.ho / NAG / (DUR/3600)
    adv = r.t5 > 0 ? (1 - r.t6/r.t5)*100 : 0.0
    push!(rows, r)
    println(rpad(string(v),8), rpad(string(r.ho),9), rpad(string(round(rate,digits=1)),12),
            rpad(string(round(r.ho_per_km,digits=3)),12),
            rpad(string(round(100r.n2_frac,digits=2)),8), round(adv,digits=1))
end

println("\nInterpretation:")
println("- If HO/km_path is ~constant across speeds => rate IS linear in speed (geometric).")
println("- If it drifts => spatial density heterogeneity / placement effect (agents that")
println("  travel further sample sparser rural cells, lowering avg HO/km).")
println("- Compare HO/km_path column to geometric ≈ $(round(geom_per_km,digits=3)).")
println("- N2% should sit near $(round(100n2_est,digits=2))% (set by UPF count, not speed).")
println("- adv% ≈ 1 - 200/600 = 66.7% whenever mix is Xn-dominated (baked into constants).")
