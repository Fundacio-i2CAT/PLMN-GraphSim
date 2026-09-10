#!/usr/bin/env julia
# Forwarding-state sensitivity analysis for the IEEE Access round-3 revision.
#
# The GUPF forwarding table is fixed by the deployed topology (one entry per
# attached gNB aggregate plus the data-network exit), so it is derivable from the
# topology alone; the 5G UPF table is exactly linear in the sessions it anchors.
# Both are therefore computed here in closed form over the same real gNB fields
# that runs/national.jl deploys, which lets us sweep the inputs a reviewer can
# reasonably question without re-running the discrete-event simulation.
#
# Experiments
#   1. operator/field profile: |P| and S_fwd per country, per gNB data source
#   2. crowdsourced vs official registry (OpenCellID vs FCC ASR / ANFR / ISED)
#   3. joint scaling: |P| against subscriber population across real deployments
#   4. UPF count / placement density sweep
#   5. market share and sessions-per-UE sensitivity of the 5G/RUPA ratio

using Pkg
Pkg.activate(joinpath(@__DIR__, "../.."))
using DesJulia6gRupa
using DesJulia6gRupa.Types
import DesJulia6gRupa.Simulation as DSim
using Printf, Logging, Random

global_logger(ConsoleLogger(stderr, Logging.Warn))

const ROOT = pkgdir(DesJulia6gRupa)
const OUT  = joinpath(ROOT, "results", "revision-r3")
mkpath(OUT)

const ADOPTION = 0.82

# Byte costs from the manuscript's idealized field-level layout (Table "state layout").
const C_SESSION_5G = 24    # 2x(FAR + tunnel), UL+DL
const C_ENTRY_RUPA = 12    # prefix + mask + port

# (key, country dir, files, operator net id, #edge UPFs, population, source label)
const PROFILES = [
    ("spain",       "spain",    ["opencellid/214.csv"],                        7,   52, 49_442_844,  "OpenCellID"),
    ("portugal",    "portugal", ["opencellid/268.csv"],                        6,   18,  9_855_909,  "OpenCellID"),
    ("france",      "france",   ["opencellid/208.csv"],                        1,   96, 66_165_815,  "OpenCellID"),
    ("france_anfr", "france",   ["anfr/208.csv"],                              1,   96, 66_165_815,  "ANFR (official)"),
    ("canada",      "canada",   ["opencellid/302.csv"],                      220,  126, 36_991_981,  "OpenCellID"),
    ("canada_ised", "canada",   ["ised/302.csv"],                            220,  126, 36_991_981,  "ISED (official)"),
    ("mexico",      "mexico",   ["opencellid/334.csv"],                       20,  445, 125_822_502, "OpenCellID"),
    ("usa",         "usa",      ["opencellid/310.csv","opencellid/311.csv"], 480,  817, 335_000_000, "OpenCellID"),
    ("usa_asr",     "usa",      ["asr/310.csv"],                             999,  817, 335_000_000, "FCC ASR (official)"),
]

function topo_for(sub, files, opid, nedge)
    base = joinpath(ROOT, "data", sub)
    paths = filter(isfile, [joinpath(base, f) for f in files])
    isempty(paths) && error("no gNB data under $base for $files")
    cfg = SimConfig(1, 2, 1000, 1.0, 1.0, 1.0, :single_tier, 0, 1.0)
    Random.seed!(20260902 + 10_000 * opid + nedge)
    return DSim.load_and_deploy_network(paths, opid, nedge, base, cfg)
end

"""Core-visible prefixes per GUPF: one per attached gNB aggregate plus one DN exit."""
function prefix_profile(topo, nupf)
    counts = zeros(Int, nupf)
    for u in topo.gnb_to_upf_map
        1 <= u <= nupf && (counts[u] += 1)
    end
    return counts .+ 1
end

mb(bytes) = bytes / 1024^2

# --------------------------------------------------------------------------
results = Dict{String,Any}()

open(joinpath(OUT, "field_profile.csv"), "w") do io
    println(io, "key,country,source,gnbs,upfs,prefixes_total,prefixes_max,prefixes_mean,",
                "population,subs,sessions,state_5g_mb,state_rupa_mb,entry_ratio,byte_ratio")
    for (key, sub, files, opid, nedge, pop, src) in PROFILES
        topo = topo_for(sub, files, opid, nedge)
        p = prefix_profile(topo, nedge)
        subs = pop * ADOPTION
        sessions = subs * 1.5           # DES-emergent mean active sessions per subscriber (config: uniform{1,2})
        s5 = sessions * C_SESSION_5G
        sr = sum(p) * C_ENTRY_RUPA
        @printf(io, "%s,%s,%s,%d,%d,%d,%d,%.1f,%d,%.0f,%.0f,%.1f,%.3f,%.1f,%.1f\n",
                key, sub, src, length(topo.gnb_locations), nedge,
                sum(p), maximum(p), sum(p)/length(p),
                pop, subs, sessions, mb(s5), mb(sr), sessions/sum(p), s5/sr)
        flush(io)
        results[key] = (gnbs=length(topo.gnb_locations), prefixes=sum(p),
                        pmax=maximum(p), subs=subs, sessions=sessions)
        println("profile $key: gnbs=$(length(topo.gnb_locations)) |P|=$(sum(p)) max=$(maximum(p))")
    end
end

# --------------------------------------------------------------------------
# UPF count / placement density sweep (USA both fields, Spain, France both fields)
open(joinpath(OUT, "upf_count_sweep.csv"), "w") do io
    println(io, "key,source,upfs,gnbs,prefixes_total,prefixes_max,state_rupa_mb")
    sweeps = Dict("spain"=>[10,26,52,104,208], "usa"=>[48,128,401,817,1600,3143],
                  "usa_asr"=>[48,128,401,817,1600,3143], "france"=>[13,48,96,192,384],
                  "france_anfr"=>[13,48,96,192,384])
    for (key, sub, files, opid, _n, _pop, src) in PROFILES
        haskey(sweeps, key) || continue
        for nupf in sweeps[key]
            topo = topo_for(sub, files, opid, nupf)
            p = prefix_profile(topo, nupf)
            @printf(io, "%s,%s,%d,%d,%d,%d,%.3f\n", key, src, nupf,
                    length(topo.gnb_locations), sum(p), maximum(p), mb(sum(p)*C_ENTRY_RUPA))
            flush(io)
            println("sweep $key upfs=$nupf |P|=$(sum(p))")
        end
    end
end

# --------------------------------------------------------------------------
# Market share x sessions-per-UE sensitivity, anchored on the USA OpenCellID field.
open(joinpath(OUT, "share_session_sweep.csv"), "w") do io
    println(io, "operator,market_share,sessions_per_ue,subs,sessions,state_5g_mb,state_rupa_mb,byte_ratio")
    base = results["usa"]
    natsubs = base.subs
    ops = [("Verizon",0.35), ("AT&T",0.30), ("T-Mobile",0.32), ("whole-nation",1.00)]
    for (op, sh) in ops, spu in (1.0, 1.5, 2.0, 3.0)
        subs = natsubs * sh
        sess = subs * spu
        s5 = sess * C_SESSION_5G
        sr = base.prefixes * C_ENTRY_RUPA
        @printf(io, "%s,%.2f,%.2f,%.0f,%.0f,%.1f,%.3f,%.1f\n",
                op, sh, spu, subs, sess, mb(s5), mb(sr), s5/sr)
    end
end

println("\nWrote CSVs to $OUT")
