#!/usr/bin/env julia
# Data for the headline figure: core forwarding-state churn vs user population.
# Spain 52 edge UPFs, Gauss-Markov 50 km/h, scale_factor=1000. Vary #agents
# (proxy for active users = agents × scale_factor). 5G writes grow O(n); RUPA = 0.

using DesJulia6gRupa, DesJulia6gRupa.Types, ConcurrentSim
import DesJulia6gRupa.Simulation as DSim

paths = filter(isfile, [joinpath(@__DIR__, "data", "spain", "opencellid", "214.csv")])
topo = DSim.load_and_deploy_network(paths, 7, 52, joinpath(@__DIR__, "data", "spain"),
                                    SimConfig(1,2,1000,1,1,1,:single_tier,0,1))
const SCALE = 1000

println("agents,users,handovers,core_writes_5g,core_writes_rupa")
for nag in (200, 400, 800, 1600, 3200)
    cfg = SimConfig(1, 2, SCALE, 300.0, 295.0, 5.0, :single_tier, 0, 10.0,
                    MobilityConfig(true, 2.0, GaussMarkov(50.0, 0.85, 5.0)))
    s = DSim.init_global_state_for_simulation(topo, cfg)
    env = ConcurrentSim.Simulation()
    @process DSim.monitor_metrics(env, s, topo, cfg.scale_factor)
    for uid in 1:nag
        @process DSim.user_lifecycle(env, uid, s, topo, eMBB)
    end
    run(env, cfg.duration)
    println("$nag,$(nag*SCALE),$(s.handover_count),$(s.core_writes_5g),$(s.core_writes_rupa)")
    flush(stdout)
end
