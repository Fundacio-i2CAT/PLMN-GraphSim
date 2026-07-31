#!/usr/bin/env julia
# Headline figure data: US core forwarding-state churn versus active users.
# Verizon OpenCellID is operator-tagged; FCC ASR is an operator-agnostic density
# upper bound. Both use 817 edge UPFs, 5 PSAs, and paired random seeds.

using DesJulia6gRupa, DesJulia6gRupa.Types, ConcurrentSim, Random
import DesJulia6gRupa.Simulation as DSim

const SCALE = 1000
const DURATION = 300.0
const AGENTS = (1_000, 5_000, 25_000, 100_000, 274_700)
const OUTPUT = get(ARGS, 1, joinpath(pkgdir(DesJulia6gRupa), "results", "churn-data-usa.csv"))
const BASE = joinpath(pkgdir(DesJulia6gRupa), "data", "usa")
const TARGETS = (
    ("verizon-opencellid", ["opencellid/310.csv", "opencellid/311.csv"], 480),
    ("fcc-asr", ["asr/310.csv"], 999),
)

function build(files, operator)
    paths = [joinpath(BASE, file) for file in files]
    all(isfile, paths) || error("missing US gNB input: $paths")
    cfg = SimConfig(1, 2, SCALE, 1, 1, 1, :two_tier, 5, 1)
    return DSim.load_and_deploy_network(paths, operator, 817, BASE, cfg)
end

function run_one(topology, n_agents)
    Random.seed!(20260731 + n_agents)
    cfg = SimConfig(1, 2, SCALE, DURATION, DURATION - 5, 5.0, :two_tier, 5, 10.0,
                    MobilityConfig(true, 2.0, GaussMarkov(120.0, 0.85, 5.0)))
    state = DSim.init_global_state_for_simulation(topology, cfg)
    env = ConcurrentSim.Simulation()
    @process DSim.monitor_metrics(env, state, topology, cfg.scale_factor)
    for uid in 1:n_agents
        @process DSim.user_lifecycle(env, uid, state, topology, eMBB)
    end
    run(env, cfg.duration)
    return state
end

open(OUTPUT, "w") do io
    println(io, "field,agents,users,handovers,core_writes_5g,core_writes_rupa")
    for (field, files, operator) in TARGETS
        topology = build(files, operator)
        for n_agents in AGENTS
            state = run_one(topology, n_agents)
            row = "$field,$n_agents,$(n_agents * SCALE),$(state.handover_count),$(state.core_writes_5g),$(state.core_writes_rupa)"
            println(io, row)
            println(row)
            flush(io)
        end
    end
end
