using Pkg
Pkg.activate(@__DIR__)

println("==========================================")
println("   6G-RUPA DES Simulation Framework       ")
println("==========================================")
println("Select an action to run:")
println("1. Fetch Population Data (INE)")
println("2. Run Full Simulation (Centralized vs Distributed)")
println("3. Plot Network Topology")
println("q. Quit")
println("==========================================")
print("Enter choice: ")

choice = strip(readline())

if choice == "1"
    println("\n>>> Running Data Fetcher...")
    include("scripts/fetch_ine_data.jl")
elseif choice == "2"
    println("\n>>> Running Simulation...")
    include("scripts/run_simulation.jl")
elseif choice == "3"
    println("\n>>> Generating Plots...")
    include("scripts/plot_topology.jl")
elseif choice == "q"
    println("Exiting...")
else
    println("Invalid choice.")
end
