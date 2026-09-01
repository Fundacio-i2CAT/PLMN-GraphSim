# Topology-driven state sensitivity for the IEEE Access revision.
#
# The GUPF forwarding table is fixed by the deployed topology (one prefix per
# attached gNB aggregate plus the data-network exit), so it can be derived from
# the topology alone without running the discrete-event simulation. The 5G UPF
# table is exactly linear in the number of sessions it anchors. This script
# reports both, sweeps the operator subscriber mapping and the UPF count, and
# writes one CSV per experiment.

using Pkg
Pkg.activate(joinpath(@__DIR__, "../.."))
using DesJulia6gRupa
using DesJulia6gRupa.DataLoading
using DesJulia6gRupa.Types
using TOML, Printf, Logging

global_logger(ConsoleLogger(stderr, Logging.Warn))

const ROOT = joinpath(@__DIR__, "../..")
const OUT = joinpath(ROOT, "results", "revision-r3")
mkpath(OUT)

cfg = TOML.parsefile(joinpath(ROOT, "config.toml"))

base_cfg(num_central=0, scenario=:single_tier) = SimConfig(
    1, 2, 1000, 100.0, 95.0, 5.0, scenario, num_central, 1.0)

"""Prefix counts seen by each edge UPF/GUPF: one per attached gNB plus one DN exit."""
function prefix_profile(topology)
    n_upf = length(topology.upf_locations)
    counts = zeros(Int, n_upf)
    for u in topology.gnb_to_upf_map
        1 <= u <= n_upf && (counts[u] += 1)
    end
    return counts .+ 1   # +1 data-network exit
end

function load_topology(country_key, op_id, num_upfs, config)
    cc = cfg["countries"][country_key]
    data_dir = joinpath(ROOT, cc["data_dir"])
    mccs = Int[]; append!(mccs, cc["mccs"])
    paths = filter(isfile, [joinpath(data_dir, "opencellid", "$(m).csv") for m in mccs])
    isempty(paths) && error("no opencellid data for $country_key")
    return load_and_deploy_network(paths, op_id, num_upfs, data_dir, config)
end

targets = [
    ("spain", "movistar", 7,   52),
    ("spain", "vodafone", 1,   52),
    ("spain", "orange",   3,   52),
    ("usa",   "verizon",  480, 817),
    ("usa",   "att",      410, 817),
    ("usa",   "tmobile",  260, 817),
]

# Reported 2025 mobile market shares (documented in the manuscript).
share = Dict("movistar"=>0.28, "vodafone"=>0.18, "orange"=>0.22,
             "verizon"=>0.35,  "att"=>0.30,      "tmobile"=>0.32)

natpop = Dict("spain"=>cfg["countries"]["spain"]["population"] * 0.82,
              "usa"  =>cfg["countries"]["usa"]["population"]   * 0.82)

# ---------- Experiment 1: baseline topology profile + market-share mapping ----------
open(joinpath(OUT, "operator_state_profile.csv"), "w") do io
    println(io, "country,operator,gnbs,upfs,prefixes_total,prefixes_max,prefixes_mean,",
                "national_subs,market_share,operator_subs,",
                "entries_5g_national,entries_5g_share,entries_rupa,",
                "ratio_national,ratio_share")
    for (ck, op, id, nupf) in targets
        topo = load_topology(ck, id, nupf, base_cfg())
        p = prefix_profile(topo)
        subs_nat = natpop[ck]
        sessions_per_ue = 1.5              # config: uniform{1,2}
        subs_op = subs_nat * share[op]
        e5_nat = subs_nat * sessions_per_ue * 2
        e5_sh  = subs_op  * sessions_per_ue * 2
        erupa  = sum(p)
        @printf(io, "%s,%s,%d,%d,%d,%d,%.2f,%.0f,%.2f,%.0f,%.0f,%.0f,%d,%.1f,%.1f\n",
            ck, op, length(topo.gnb_locations), nupf, sum(p), maximum(p), sum(p)/length(p),
            subs_nat, share[op], subs_op, e5_nat, e5_sh, erupa,
            e5_nat/erupa, e5_sh/erupa)
        flush(io)
        println("done: $ck/$op gnbs=$(length(topo.gnb_locations)) prefixes=$(sum(p))")
    end
end

# ---------- Experiment 2: UPF count / placement density sweep ----------
open(joinpath(OUT, "upf_count_sweep.csv"), "w") do io
    println(io, "country,operator,upfs,gnbs,prefixes_total,prefixes_max,prefixes_mean")
    for (ck, op, id, _) in targets
        for nupf in (ck == "usa" ? [48, 128, 401, 817, 1600, 3143] : [10, 26, 52, 104, 208])
            topo = load_topology(ck, op == "movistar" || op == "verizon" ? id : id, nupf, base_cfg())
            p = prefix_profile(topo)
            @printf(io, "%s,%s,%d,%d,%d,%d,%.2f\n",
                ck, op, nupf, length(topo.gnb_locations), sum(p), maximum(p), sum(p)/length(p))
            flush(io)
            println("sweep: $ck/$op upfs=$nupf prefixes=$(sum(p)) max=$(maximum(p))")
        end
    end
end

# ---------- Experiment 3: gNB density (OpenCellID completeness / densification) ----------
# Subsample the operator's cell set to emulate an incomplete database, and
# extrapolate above 1.0 to emulate densification.
open(joinpath(OUT, "gnb_density_sweep.csv"), "w") do io
    println(io, "country,operator,upfs,frac,gnbs_used,prefixes_total,prefixes_max")
    for (ck, op, id, nupf) in [("spain","movistar",7,52), ("usa","verizon",480,817)]
        topo = load_topology(ck, id, nupf, base_cfg())
        p_full = prefix_profile(topo)
        ngnb = length(topo.gnb_locations)
        for frac in [0.25, 0.5, 0.75, 1.0]
            # deterministic stride subsample of the gNB->UPF assignment
            step = max(1, round(Int, 1/frac))
            counts = zeros(Int, nupf)
            used = 0
            for (i, u) in enumerate(topo.gnb_to_upf_map)
                if i % step == 0 && 1 <= u <= nupf
                    counts[u] += 1; used += 1
                end
            end
            counts .+= 1
            @printf(io, "%s,%s,%d,%.2f,%d,%d,%d\n",
                ck, op, nupf, frac, used, sum(counts), maximum(counts))
            flush(io)
        end
        println("density done: $ck/$op full_gnbs=$ngnb full_prefixes=$(sum(p_full))")
    end
end

println("\nWrote CSVs to $OUT")
