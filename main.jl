#!/usr/bin/env julia
# Single entry point for every evaluation run.
#
#   julia --project main.jl                       # interactive menu
#   julia --project main.jl list                  # list available runs
#   julia --project main.jl <run> [args...]       # parametric dispatch, e.g.:
#   julia --project main.jl national spain
#   julia --project main.jl national usa 0.05
#   julia --project main.jl iberia reestablish 500 300
#   julia --project main.jl federation reestablish 0 1200 all
#   julia --project main.jl trajectories
#
# Runs live in runs/*.jl (one file per evaluation; legacy one-offs under
# runs/legacy/, runnable by name too). Each run script documents its own
# arguments in its header comment, shown by the menu and by `list`.

using Pkg
Pkg.activate(@__DIR__)

const RUNS_DIR = joinpath(@__DIR__, "runs")
const LEGACY_DIR = joinpath(RUNS_DIR, "legacy")

struct RunEntry
    name::String
    path::String
    description::String     # first comment line of the header
    usage::Vector{String}   # header lines showing example invocations
    legacy::Bool
end

function parse_header(path::String, name::String, legacy::Bool)
    description = ""
    usage = String[]
    for line in eachline(path)
        startswith(line, "#!") && continue
        startswith(line, "#") || break              # header comment block ended
        text = strip(lstrip(strip(line), '#'))
        isempty(text) && continue
        if occursin("julia --project", text)
            # Normalize old direct-invocation examples to the dispatcher form.
            push!(usage, replace(text,
                r"julia --project (?:main\.jl )?(?:runs/)?(?:run_|gen_)?[A-Za-z_0-9]+\.?j?l?" =>
                "julia --project main.jl $name"))
        elseif isempty(description)
            description = text
        end
    end
    return RunEntry(name, path, description, usage, legacy)
end

function discover_runs()
    entries = RunEntry[]
    for f in sort(readdir(RUNS_DIR))
        endswith(f, ".jl") || continue
        push!(entries, parse_header(joinpath(RUNS_DIR, f), replace(f, ".jl" => ""), false))
    end
    if isdir(LEGACY_DIR)
        for f in sort(readdir(LEGACY_DIR))
            endswith(f, ".jl") || continue
            name = replace(f, ".jl" => "")
            push!(entries, parse_header(joinpath(LEGACY_DIR, f), name, true))
        end
    end
    return entries
end

function print_runs(entries; legacy=false)
    for (i, e) in enumerate(entries)
        e.legacy == legacy || continue
        println("  ", rpad(string(i, ". ", e.name), 32), e.description)
    end
end

function launch(entry::RunEntry, args::Vector{String})
    println(">>> $(entry.name) $(join(args, ' '))")
    empty!(ARGS)
    append!(ARGS, args)
    include(entry.path)
end

function interactive(entries)
    println("==========================================")
    println("   6G-RUPA DES Simulation Framework       ")
    println("==========================================")
    print_runs(entries; legacy=false)
    println("  ", rpad("s. simulation", 32), "Full simulation (centralized vs distributed)")
    println("  ", rpad("p. plot topology", 32), "Plot network topology")
    println("  ", rpad("l. legacy", 32), "Show legacy one-off runs")
    println("  ", rpad("q. quit", 32))
    println("==========================================")
    print("Enter choice: ")
    choice = strip(readline())

    if choice == "q"
        return
    elseif choice == "s"
        println("\n>>> Running simulation...")
        include(joinpath(@__DIR__, "scripts", "run_simulation.jl"))
        return
    elseif choice == "p"
        println("\n>>> Generating plots...")
        include(joinpath(@__DIR__, "scripts", "plot-topology", "plot_all_topology.jl"))
        return
    elseif choice == "l"
        println()
        print_runs(entries; legacy=true)
        print("Enter choice: ")
        choice = strip(readline())
    end

    idx = tryparse(Int, choice)
    (idx === nothing || !(1 <= idx <= length(entries))) && (println("Invalid choice."); return)
    entry = entries[idx]
    if !isempty(entry.usage)
        println()
        foreach(u -> println("  ", u), entry.usage)
    end
    print("Arguments (space-separated, empty = defaults): ")
    args = String.(split(strip(readline())))
    launch(entry, args)
end

entries = discover_runs()

if isempty(ARGS)
    interactive(entries)
elseif ARGS[1] == "list"
    println("Runs (julia --project main.jl <run> [args...]):")
    print_runs(entries; legacy=false)
    println("Legacy:")
    print_runs(entries; legacy=true)
else
    name = ARGS[1]
    args = String.(ARGS[2:end])
    i = findfirst(e -> e.name == name, entries)
    if i === nothing
        println("Unknown run '$name'. Available:")
        print_runs(entries; legacy=false)
        exit(1)
    end
    launch(entries[i], args)
end
