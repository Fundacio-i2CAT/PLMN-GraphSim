#!/usr/bin/env julia
# Layer-stack snapshot export for the graph-of-graphs visualization.
#   julia --project main.jl layers_viz            # full pan-Iberian members
#
# Builds the K=5 pan-Iberian federation (same members as runs/federation.jl),
# then TWO stacks over the same physical substrate:
#   flat.json      — the §7.5.1 shape: one internetwork layer over 5 members
#   hierarchy.json — the recursive shape: exchange-es over the 3 Spanish
#                    members, exchange-pt over the 2 Portuguese ones, eu-root
#                    over both exchanges, and the Starlink NTN member enrolled
#                    at the root (N layers over M sublayers, DAG not tree)
# Output: viz/data/layers_{flat,hierarchy}.json for viz/layers.html.

using DesJulia6gRupa
using DesJulia6gRupa.Types
import DesJulia6gRupa.Simulation as DSim
import DesJulia6gRupa.DataLoading as DL

const MEMBERS = [
    ("Movistar ES", "spain",    ["opencellid/214.csv"], 7, 52, 5),
    ("MEO PT",      "portugal", ["opencellid/268.csv"], 6, 18, 2),
    ("Orange ES",   "spain",    ["opencellid/214.csv"], 3, 52, 5),
    ("Vodafone ES", "spain",    ["opencellid/214.csv"], 1, 52, 5),
    ("Vodafone PT", "portugal", ["opencellid/268.csv"], 1, 18, 2),
]

function build_member(sub, files, opid, nedge, npsa)
    base = joinpath(pkgdir(DesJulia6gRupa), "data", sub)
    paths = filter(isfile, [joinpath(base, f) for f in files])
    isempty(paths) && error("no gNB data under $base for $files")
    cfg = SimConfig(1, 2, 1000, 1, 1, 1, :two_tier, npsa, 1)
    return DL.load_and_deploy_network(paths, opid, nedge, base, cfg)
end

members = [build_member(m[2], m[3], m[4], m[5], m[6]) for m in MEMBERS]
composed = DL.compose_topologies(members)
outdir = joinpath(pkgdir(DesJulia6gRupa), "viz", "data")
mkpath(outdir)

# Flat stack: internetwork over all 5 members (§7.5.1 as-simulated).
flat = DSim.build_layer_stack(composed)
DSim.export_layer_stack_json(flat, joinpath(outdir, "layers_flat.json"))

# Hierarchical stack: exchanges + root + NTN (the recursion demo).
h = DSim.build_layer_stack(composed; internetwork = false)
# Member layer names are member-<operator tag>; tags follow composition order
# 1..5 = Movistar ES, MEO PT, Orange ES, Vodafone ES, Vodafone PT.
m = [DSim.layer_by_name(h, "member-$i").id for i in 1:5]
ex_es = DSim.add_federation_layer!(h, [m[1], m[3], m[4]]; name = "exchange-es")
ex_pt = DSim.add_federation_layer!(h, [m[2], m[5]]; name = "exchange-pt")
root = DSim.add_federation_layer!(h, [ex_es, ex_pt]; name = "eu-root")

# NTN member: Starlink 550 shell, GUPF per satellite over Iberia at t=0.
tle = joinpath(pkgdir(DesJulia6gRupa), "data", "ntn", "tles_starlink_550_sgp.txt")
if isfile(tle)
    c = DSim.load_constellation(tle; operator_id = 99)
    DSim.positions_at!(c, 0.0)
    E = length(composed.upf_locations); P = length(composed.centralized_upf_locations)
    over = [i for i in 1:DSim.n_satellites(c)
            if 30.0 <= c.cache_lat[i] <= 46.0 && -12.0 <= c.cache_lon[i] <= 6.0]
    nodes = [E + P + k for k in eachindex(over)]
    locs = [GeoPoint(c.cache_lat[s], c.cache_lon[s]) for s in over]
    sat = DSim.add_member_layer!(h, nodes; name = "ntn-starlink", locations = locs)
    DSim.enroll!(h, root, sat)
    @info "NTN member: $(length(over)) Starlink satellites over Iberia at t=0"
end

DSim.export_layer_stack_json(h, joinpath(outdir, "layers_hierarchy.json"))
@info "exported" joinpath(outdir, "layers_flat.json") joinpath(outdir, "layers_hierarchy.json")
