using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using DesJulia6gRupa
using DesJulia6gRupa.Simulation

function run_all_scenarios()
    # Scale Factor: 1 Agent represents X real users
    # Options: 100, 1000, 10000
    SCALE = 1000 

    # Scenario 1: Centralized (Legacy 4G-like) - 3 UPFs (e.g., Madrid, Barcelona, Seville)
    println("\n>>> SCENARIO 1: CENTRALIZED (Legacy 4G-like) - 3 UPFs <<<")
    run_operator_simulation("Vodafone", 1, 3, "Centralized"; scale_factor=SCALE)
    run_operator_simulation("Orange", 3, 3, "Centralized"; scale_factor=SCALE)
    run_operator_simulation("Movistar", 7, 3, "Centralized"; scale_factor=SCALE)

    # Scenario 2: Distributed (5G Edge) - 52 UPFs (Provincial)
    println("\n>>> SCENARIO 2: DISTRIBUTED (5G Edge) - 52 UPFs <<<")
    run_operator_simulation("Vodafone", 1, 52, "Distributed"; scale_factor=SCALE)
    run_operator_simulation("Orange", 3, 52, "Distributed"; scale_factor=SCALE)
    run_operator_simulation("Movistar", 7, 52, "Distributed"; scale_factor=SCALE)
end

run_all_scenarios()
