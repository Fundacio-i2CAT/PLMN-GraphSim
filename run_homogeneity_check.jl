#!/usr/bin/env julia
# Homogeneity control: same Gauss-Markov speed sweep on a SYNTHETIC uniform gNB
# field at Spain's mean density. On a homogeneous field, HO per km of path must be
# (a) ~constant across speed and (b) close to the Poisson-Voronoi prediction
# (4/pi)*sqrt(λ). If so, the sublinear HO/km seen on the REAL topology is caused
# by spatial density heterogeneity (urban clustering + placement), not a simulator
# bug. This isolates cause from artifact.

using DesJulia6gRupa
using DesJulia6gRupa.Types
using ConcurrentSim
using Clustering
using Random
using Graphs
using MetaGraphsNext
import DesJulia6gRupa.Simulation as DSim

Random.seed!(42)

const NGNB = 46396
const N_UPFS = 20
const DUR = 1200
const DT = 2
const NAG = 1000

# Box sized to Spain's mean density λ = NGNB / 505000 km^2.
# Use a square in degrees near Madrid; convert target area to a lat/lon span.
const AREA_KM2 = 505_000.0
λ = NGNB / AREA_KM2
side_km = sqrt(AREA_KM2)                      # ~711 km square
const REF_LAT = 40.0
mPerDegLat = 111_132.0
mPerDegLon = 111_132.0 * cos(deg2rad(REF_LAT))
dlat = (side_km * 1000.0) / mPerDegLat
dlon = (side_km * 1000.0) / mPerDegLon
lat0, lon0 = REF_LAT - dlat/2, -3.7 - dlon/2

# Uniform-random gNBs over the box (homogeneous Poisson field).
gnb = [GeoPoint(lat0 + rand()*dlat, lon0 + rand()*dlon) for _ in 1:NGNB]

# K-means UPF clustering (same as real pipeline).
lats = [p.lat for p in gnb]; lons = [p.lon for p in gnb]
km = kmeans(hcat(lats, lons)', N_UPFS)
g2u = km.assignments
upf = [GeoPoint(km.centers[1,i], km.centers[2,i]) for i in 1:N_UPFS]

topo = NetworkTopology(
    gnb, upf, g2u, GeoPoint[], Int[],
    Municipality[], Dict{String,Vector{Int}}(), Float64[],
    MetaGraph(Graph(), label_type=Tuple{Symbol,Int}, vertex_data_type=GeoPoint, edge_data_type=Float64),
)

geom_per_km = (4/π) * sqrt(λ)
println("SYNTHETIC homogeneous field: $NGNB gNBs over $(round(side_km))km box, λ=$(round(λ,digits=4))/km^2")
println("Geometric prediction (4/π)√λ = $(round(geom_per_km,digits=3)) HO/km (straight line)\n")
println(rpad("speed",8), rpad("HO",9), rpad("HO/km_path",12), rpad("N2%",8), "adv%")

for v in (5, 20, 50, 80, 120)
    model = GaussMarkov(Float64(v), 0.85, 5.0)
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
    path_km = v * DUR / 3600
    ho_per_km = (ho/NAG) / path_km
    t5 = s.sigma_5g_xn + s.sigma_5g_n2; t6 = s.sigma_rupa_intra + s.sigma_rupa_inter
    adv = t5 > 0 ? (1 - t6/t5)*100 : 0.0
    println(rpad(string(v),8), rpad(string(ho),9),
            rpad(string(round(ho_per_km,digits=3)),12),
            rpad(string(round(100*n2ev/max(ho,1),digits=2)),8), round(adv,digits=1))
end

println("\nExpect: HO/km_path ~constant across speed and near $(round(geom_per_km,digits=3)).")
println("If flat here but sloped on real topology => real-data slope is spatial heterogeneity.")
