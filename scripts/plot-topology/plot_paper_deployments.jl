#!/usr/bin/env julia
# Figure 5 of the IEEE Access paper "Beyond 5G Architectural Constraints":
# the national topology-record fields used for the forwarding-state calculation.
#
# Uses the simulator's own topology loader (load_and_deploy_network), so the
# attachment-point records and UPF placement drawn here match the state inputs:
# 113,210 records / 817 UPFs for Verizon (USA) and 46,396 records /
# 52 UPFs for Movistar (Spain).
#
#   julia --project=. scripts/plot-topology/plot_paper_deployments.jl [output-dir] [basename]
#
# Writes images/paper_topology_deployments.{pdf,png}; the paper embeds the PNG as
# figures/topology_deployments.png.

using Pkg
Pkg.activate(joinpath(@__DIR__, "../.."))
using DesJulia6gRupa, DesJulia6gRupa.Types
import DesJulia6gRupa.Simulation as DSim
using Plots
using Random
gr()

# k-means placement draws from the global RNG, so seed it: the figure is then
# deterministic. The cluster COUNT is fixed by configuration either way, and
# that count is what the reported state figures depend on, not where the
# centroids land.
Random.seed!(20260902)

const BASE_US = joinpath(pkgdir(DesJulia6gRupa), "data", "usa")
const BASE_ES = joinpath(pkgdir(DesJulia6gRupa), "data", "spain")
const OUT = isempty(ARGS) ? joinpath(pkgdir(DesJulia6gRupa), "images") : abspath(ARGS[1])
const BASENAME = get(ARGS, 2, "paper_topology_deployments")
mkpath(OUT)

# Only the topology matters here; the traffic parameters are unused by the loader.
cfg = SimConfig(1, 2, 1000, 1, 1, 1, :single_tier, 0, 1)

function load(base, files, opid, nupf)
    paths = filter(isfile, [joinpath(base, f) for f in files])
    DSim.load_and_deploy_network(paths, opid, nupf, base, cfg)
end

println("loading USA / Verizon ...")
us = load(BASE_US, ["opencellid/310.csv", "opencellid/311.csv"], 480, 817)
println("loading Spain / Movistar ...")
es = load(BASE_ES, ["opencellid/214.csv"], 7, 52)

grp(n) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")

function panel(topo, title_str, xl, yl; upf_ms=2.0, gnb_ms=1.0)
    glon = [p.lon for p in topo.gnb_locations]; glat = [p.lat for p in topo.gnb_locations]
    ulon = [p.lon for p in topo.upf_locations]; ulat = [p.lat for p in topo.upf_locations]
    p = plot(; title=title_str, titlefontsize=15, legend=:bottomleft, legendfontsize=11,
             xlabel="Longitude", ylabel="Latitude", guidefontsize=12, tickfontsize=11,
             xlims=xl, ylims=yl, grid=false, framestyle=:box, background_color=:white)
    scatter!(p, glon, glat; label="gNBs ($(grp(length(glon))))", markersize=gnb_ms,
             markercolor=:steelblue, markeralpha=0.35, markerstrokewidth=0)
    scatter!(p, ulon, ulat; label="UPFs ($(grp(length(ulon))))",
             markersize=upf_ms, markercolor=:orangered, markershape=:circle,
             markerstrokewidth=0, markeralpha=0.9)
    p
end

pUS = panel(us, "USA (Verizon): $(grp(length(us.gnb_locations))) gNBs, 817 UPFs",
            (-125.5, -66.5), (24.0, 49.8); upf_ms=2.4, gnb_ms=1.0)
pES = panel(es, "Spain (Movistar): $(grp(length(es.gnb_locations))) gNBs, 52 UPFs",
            (-9.6, 4.5), (35.7, 43.9); upf_ms=5.0, gnb_ms=1.3)

# Sized for a two-column-span figure* in the IEEE Access template.
fig = plot(pUS, pES; layout=(1, 2), size=(1900, 600), dpi=170, left_margin=9Plots.mm,
           bottom_margin=10Plots.mm, right_margin=3Plots.mm, top_margin=2Plots.mm)
savefig(fig, joinpath(OUT, "$BASENAME.pdf"))
savefig(fig, joinpath(OUT, "$BASENAME.png"))
println("wrote ", joinpath(OUT, "$BASENAME.{pdf,png}"))
