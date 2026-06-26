#!/usr/bin/env julia
# Trajectory export for the deck.gl mobility demo (terrestrial analog of the
# LEOPath/Cesium satellite viz). Samples N agents on the REAL principled topology
# (Spain 52 edge UPFs / 5 PSAs, population-weighted initial placement), walks each
# under the chosen mobility model, and records its path + handover events
# (classified L1/L2/L3). Writes viz/data/{trajectories,gnbs,meta}.json.
#
#   julia --project gen_trajectories.jl [country] [n_agents] [duration_s] [dt_s] [speed_kmh]
#     country = spain | usa | usa_asr   (default spain; agent count defaults to national)
#
# No full DES needed: we just iterate step_position + find_serving_gnb per agent,
# exactly the per-tick handover check Core.jl does, so levels match the national run.

using DesJulia6gRupa, DesJulia6gRupa.Types
import DesJulia6gRupa.Simulation as DSim
import DesJulia6gRupa: select_agent_location

# (data subdir, gNB csv files rel to data/<sub>, operator net id, #edge UPFs, population)
# Mirrors run_national.jl PROFILES so trajectory levels match the national run.
const PROFILES = Dict(
    "spain"   => ("spain", ["opencellid/214.csv"],                      7,  52,  49_442_844),
    "usa"     => ("usa",   ["opencellid/310.csv","opencellid/311.csv"], 480, 817, 335_000_000),
    "usa_asr" => ("usa",   ["asr/310.csv"],                             999, 817, 335_000_000),
)
const SCALE    = 1000
const ADOPTION = 0.82
const NUM_PSA  = 5

const COUNTRY  = lowercase(get(ARGS, 1, "spain"))
haskey(PROFILES, COUNTRY) || error("unknown country $COUNTRY (spain|usa|usa_asr)")
const SUB, FILES, OPID, NEDGE, POP = PROFILES[COUNTRY]
const NAG      = length(ARGS) >= 2 ? parse(Int,   ARGS[2]) : ceil(Int, POP*ADOPTION/SCALE)
const DURATION = length(ARGS) >= 3 ? parse(Float64,ARGS[3]) : 600.0
const DT       = length(ARGS) >= 4 ? parse(Float64,ARGS[4]) : 4.0
const SPEED    = length(ARGS) >= 5 ? parse(Float64,ARGS[5]) : 50.0
const NSTEPS   = floor(Int, DURATION / DT)

r5(x) = round(x, digits=5)      # coord rounding to shrink the file

println("Building $(uppercase(COUNTRY)) topology ($NEDGE edge / $NUM_PSA PSA, two_tier)...")
base = joinpath(@__DIR__, "data", SUB)
paths = filter(isfile, [joinpath(base, f) for f in FILES])
isempty(paths) && error("no gNB data under $base for $FILES")
topo = DSim.load_and_deploy_network(paths, OPID, NEDGE, base,
                                    SimConfig(1,2,SCALE,1,1,1,:two_tier,NUM_PSA,1))
println("gNBs=$(length(topo.gnb_locations)) edgeUPF=$(length(topo.upf_locations)) PSA=$(length(topo.centralized_upf_locations))")

model = RandomWaypoint(SPEED, 0.0, SPEED*DT/3600*2)   # max jump ~2 steps of travel

outdir = joinpath(@__DIR__, "viz", "data")
mkpath(outdir)

println("Generating $NAG trajectories, $NSTEPS steps @ dt=$(DT)s ($(DURATION)s, $(SPEED) km/h)...")
function gen_trips(io, topo, model)
nho = 0
for a in 1:NAG
    loc = select_agent_location(topo)
    mstate = MobilityState(loc, 0.0, 0.0, 0.0, 0.0)
    gnb = DSim.find_serving_gnb(topo, loc)
    upf = gnb > 0 ? topo.gnb_to_upf_map[gnb] : 0

    lons = Float64[r5(loc.lon)]; lats = Float64[r5(loc.lat)]; tss = Int[0]
    ho_lon = Float64[]; ho_lat = Float64[]; ho_t = Int[]; ho_lvl = Int[]
    for s in 1:NSTEPS
        t = round(Int, s*DT)
        loc = DSim.step_position(model, loc, mstate, DT)
        push!(lons, r5(loc.lon)); push!(lats, r5(loc.lat)); push!(tss, t)
        ng = DSim.find_serving_gnb(topo, loc)
        if ng > 0 && ng != gnb
            nupf = topo.gnb_to_upf_map[ng]
            lvl = DSim.handover_level(topo, upf, nupf)
            push!(ho_lon, r5(loc.lon)); push!(ho_lat, r5(loc.lat)); push!(ho_t, t); push!(ho_lvl, lvl)
            gnb = ng; upf = nupf; nho += 1
        end
    end

    a > 1 && print(io, ",")
    print(io, "{\"path\":[")
    for i in eachindex(lons)
        i > 1 && print(io, ",")
        print(io, "[", lons[i], ",", lats[i], "]")
    end
    print(io, "],\"ts\":[", join(tss, ","), "],\"ho\":[")
    for i in eachindex(ho_t)
        i > 1 && print(io, ",")
        print(io, "[", ho_lon[i], ",", ho_lat[i], ",", ho_t[i], ",", ho_lvl[i], "]")
    end
    print(io, "]}")
    a % 200 == 0 && (println("  ...$a agents ($nho handovers)"); flush(stdout))
end
return nho
end

io = open(joinpath(outdir, "trajectories-$COUNTRY.json"), "w")
print(io, "[")
nho = gen_trips(io, topo, model)
print(io, "]")
close(io)
println("Wrote trajectories-$COUNTRY.json  ($NAG agents, $nho handovers)")

# gNB sites (rounded). 46k points render fine in deck.gl.
open(joinpath(outdir, "gnbs-$COUNTRY.json"), "w") do f
    print(f, "[")
    for (i, g) in enumerate(topo.gnb_locations)
        i > 1 && print(f, ",")
        print(f, "[", round(g.lon,digits=4), ",", round(g.lat,digits=4), "]")
    end
    print(f, "]")
end
println("Wrote gnbs-$COUNTRY.json  ($(length(topo.gnb_locations)) sites)")

open(joinpath(outdir, "meta-$COUNTRY.json"), "w") do f
    print(f, "{\"country\":\"$COUNTRY\",\"agents\":$NAG,\"duration\":$(round(Int,DURATION)),",
            "\"dt\":$(round(Int,DT)),\"speed_kmh\":$SPEED,\"nsteps\":$NSTEPS,",
            "\"edge_upfs\":$NEDGE,\"psas\":$NUM_PSA,\"handovers\":$nho}")
end
println("Done. Output in $outdir")
