#!/usr/bin/env julia
# Static trajectory export for the browser frontend.
#
# Frontend stays pure static under frontend/. This Julia script is only an
# offline precompute step: it reads simulator config/data, writes JSON bundles,
# then updates frontend/data/manifest.json so frontend/index.html can offer
# country/operator/scale selectors without any backend.
#
# Usage:
#   julia --project=. gen_trajectories.jl [country|all] [operator|all] [scale[,scale...]] [mobility|all] [duration_s] [dt_s]
#
# Examples:
#   julia --project=. gen_trajectories.jl spain movistar 10000 urban_50 1200 2
#   julia --project=. gen_trajectories.jl usa verizon 50000,25000,10000 all 1200 2
#   julia --project=. gen_trajectories.jl all all 100000,50000 paper 1200 2

using Dates
using JSON
using TOML
using DesJulia6gRupa, DesJulia6gRupa.Types
import DesJulia6gRupa.Simulation as DSim
import DesJulia6gRupa: select_agent_location

const CONFIG_PATH = joinpath(@__DIR__, "config.toml")
const OUTDIR = get(ENV, "FRONTEND_DATA_DIR", joinpath(@__DIR__, "frontend", "data"))
const NUM_PSA = 5
const DEFAULT_COUNTRY = "spain"
const DEFAULT_OPERATOR = "movistar"
const SCALE_PRESETS = [100_000, 50_000, 25_000, 10_000, 5_000, 1_000]
const DEFAULT_SCALES = [100_000, 50_000, 25_000]
const DEFAULT_MOBILITY_IDS = ["pedestrian_5", "urban_50", "highway_120"]
const DEFAULT_DURATION = 1200.0
const DEFAULT_DT = 2.0

const MOBILITY_PROFILES = [
    Dict(
        "id" => "pedestrian_5",
        "label" => "Pedestrian 5 km/h (Random Waypoint)",
        "short_label" => "Pedestrian 5",
        "model" => "random_waypoint",
        "speed_kmh" => 5.0,
        "pause_time" => 0.0,
        "max_jump_km" => 2.0,
    ),
    Dict(
        "id" => "urban_50",
        "label" => "Urban 50 km/h (Random Waypoint)",
        "short_label" => "Urban 50",
        "model" => "random_waypoint",
        "speed_kmh" => 50.0,
        "pause_time" => 0.0,
        "max_jump_km" => 20.0,
    ),
    Dict(
        "id" => "highway_120",
        "label" => "Highway 120 km/h (Gauss-Markov)",
        "short_label" => "Highway 120",
        "model" => "gauss_markov",
        "speed_kmh" => 120.0,
        "alpha" => 0.85,
        "max_acceleration" => 5.0,
    ),
]

const MOBILITY_ALIASES = Dict(
    "pedestrian" => "pedestrian_5",
    "pedestrian_5" => "pedestrian_5",
    "pedestrian5" => "pedestrian_5",
    "urban" => "urban_50",
    "urban_50" => "urban_50",
    "urban50" => "urban_50",
    "highway" => "highway_120",
    "highway_120" => "highway_120",
    "highway120" => "highway_120",
)

const COUNTRY_LABELS = Dict(
    "spain" => "Spain",
    "usa" => "USA",
    "usa_asr" => "USA ASR",
)

const OPERATOR_LABELS = Dict(
    "asr" => "ASR macro",
    "att" => "AT&T",
    "tmobile" => "T-Mobile",
)

const COUNTRY_VIEWS = Dict(
    "spain" => Dict("longitude" => -3.6, "latitude" => 40.2, "zoom" => 5.3, "pitch" => 0, "bearing" => 0),
    "usa" => Dict("longitude" => -98.5, "latitude" => 39.8, "zoom" => 3.4, "pitch" => 0, "bearing" => 0),
    "usa_asr" => Dict("longitude" => -98.5, "latitude" => 39.8, "zoom" => 3.4, "pitch" => 0, "bearing" => 0),
)

const VIRTUAL_COUNTRIES = Dict(
    "usa_asr" => Dict(
        "enabled" => true,
        "data_dir" => "data/usa",
        "gnb_files" => ["asr/310.csv"],
        "population" => 335_000_000,
        "mobile_adoption_rate" => 0.82,
        "scenarios" => Dict("USA ASR Distributed" => 817),
        "operators" => Dict("asr" => Dict("id" => 999, "enabled" => true)),
    ),
)

const DEFAULT_VIEW = Dict("longitude" => 0.0, "latitude" => 20.0, "zoom" => 2.0, "pitch" => 0, "bearing" => 0)

r5(x) = round(x, digits=5)

function labelize(id::AbstractString)
    words = split(replace(String(id), "_" => " "), " ")
    return join(uppercasefirst.(words), " ")
end

country_label(country::AbstractString) = get(COUNTRY_LABELS, String(country), labelize(country))
operator_label(operator::AbstractString) = get(OPERATOR_LABELS, String(operator), labelize(operator))

function mobility_profile(id::AbstractString)
    key = get(MOBILITY_ALIASES, lowercase(strip(String(id))), lowercase(strip(String(id))))
    for profile in MOBILITY_PROFILES
        profile["id"] == key && return profile
    end
    error("unknown mobility profile '$id' (use pedestrian_5, urban_50, highway_120, paper, or all)")
end

function mobility_order(id::AbstractString)
    key = get(MOBILITY_ALIASES, lowercase(strip(String(id))), lowercase(strip(String(id))))
    for (i, profile) in enumerate(MOBILITY_PROFILES)
        profile["id"] == key && return i
    end
    return length(MOBILITY_PROFILES) + 1
end

function mobility_model(profile)
    if profile["model"] == "random_waypoint"
        return RandomWaypoint(Float64(profile["speed_kmh"]),
                              Float64(profile["pause_time"]),
                              Float64(profile["max_jump_km"]))
    elseif profile["model"] == "gauss_markov"
        return GaussMarkov(Float64(profile["speed_kmh"]),
                           Float64(profile["alpha"]),
                           Float64(profile["max_acceleration"]))
    end
    error("unsupported mobility model $(profile["model"])")
end

function parse_mobility_profiles(arg::AbstractString)
    key = lowercase(strip(arg))
    key in ("all", "paper", "default") && return [mobility_profile(id) for id in DEFAULT_MOBILITY_IDS]
    profiles = Any[]
    for item in split(arg, ",")
        s = strip(item)
        isempty(s) && continue
        push!(profiles, mobility_profile(s))
    end
    isempty(profiles) && error("no mobility profiles parsed from '$arg'")
    return profiles
end

function parse_scales(arg::AbstractString)
    lowercase(strip(arg)) == "default" && return DEFAULT_SCALES
    scales = Int[]
    for item in split(arg, ",")
        s = strip(item)
        isempty(s) && continue
        push!(scales, parse(Int, s))
    end
    isempty(scales) && error("no scales parsed from '$arg'")
    any(<=(0), scales) && error("scale factors must be positive")
    return scales
end

function enabled_country_keys(toml_data)
    countries = all_countries(toml_data)
    return sort([String(k) for k in keys(countries) if get(countries[k], "enabled", false)])
end

function all_countries(toml_data)
    countries = Dict{String,Any}()
    for (key, cfg) in toml_data["countries"]
        countries[String(key)] = cfg
    end
    for (key, cfg) in VIRTUAL_COUNTRIES
        countries[key] = cfg
    end
    return countries
end

function selected_countries(toml_data, arg::AbstractString)
    countries = all_countries(toml_data)
    key = lowercase(strip(arg))
    if key == "all"
        return enabled_country_keys(toml_data)
    end
    haskey(countries, key) || error("unknown country '$key' in config.toml")
    get(countries[key], "enabled", false) || error("country '$key' is disabled in config.toml")
    return [key]
end

function selected_operators(country_config, arg::AbstractString)
    operators = country_config["operators"]
    key = lowercase(strip(arg))
    if key == "all"
        return sort([String(k) for k in keys(operators) if get(operators[k], "enabled", false)])
    end
    haskey(operators, key) || error("unknown operator '$key' for selected country")
    get(operators[key], "enabled", false) || error("operator '$key' is disabled in config.toml")
    return [key]
end

function country_mccs(country_config)
    if haskey(country_config, "mccs")
        return Int.(country_config["mccs"])
    elseif haskey(country_config, "mcc")
        return [Int(country_config["mcc"])]
    end
    error("country has neither mcc nor mccs in config.toml")
end

function country_edge_upfs(country_config)
    scenarios = get(country_config, "scenarios", Dict())
    isempty(scenarios) && error("country has no scenarios in config.toml")
    return maximum(Int.(collect(values(scenarios))))
end

function gnb_paths(data_dir::String, country_config)
    if haskey(country_config, "gnb_files")
        return filter(isfile, [joinpath(data_dir, f) for f in country_config["gnb_files"]])
    end
    paths = [joinpath(data_dir, "opencellid", "$(mcc).csv") for mcc in country_mccs(country_config)]
    return filter(isfile, paths)
end

function build_topology(country::String, operator::String, country_config, scale_factor::Int)
    data_dir = joinpath(@__DIR__, String(country_config["data_dir"]))
    paths = gnb_paths(data_dir, country_config)
    isempty(paths) && error("no OpenCellID data files found under $data_dir/opencellid")

    operator_id = Int(country_config["operators"][operator]["id"])
    nedge = country_edge_upfs(country_config)
    cfg = SimConfig(1, 2, scale_factor, 1, 1, 1, :two_tier, NUM_PSA, 1)

    println("Building $(country_label(country)) / $(operator_label(operator)) topology ($nedge edge / $NUM_PSA PSA)...")
    topo = DSim.load_and_deploy_network(paths, operator_id, nedge, data_dir, cfg)
    println("gNBs=$(length(topo.gnb_locations)) edgeUPF=$(length(topo.upf_locations)) PSA=$(length(topo.centralized_upf_locations))")
    return topo, nedge
end

function write_gnbs(path::String, topo)
    open(path, "w") do io
        print(io, "[")
        for (i, g) in enumerate(topo.gnb_locations)
            i > 1 && print(io, ",")
            print(io, "[", round(g.lon, digits=4), ",", round(g.lat, digits=4), "]")
        end
        print(io, "]")
    end
end

function gen_trips(io, topo, model, n_agents::Int, nsteps::Int, dt::Float64)
    nho = 0
    for a in 1:n_agents
        loc = select_agent_location(topo)
        mstate = MobilityState(loc, 0.0, 0.0, 0.0, 0.0)
        gnb = DSim.find_serving_gnb(topo, loc)
        upf = gnb > 0 ? topo.gnb_to_upf_map[gnb] : 0

        lons = Float64[r5(loc.lon)]
        lats = Float64[r5(loc.lat)]
        tss = Int[0]
        ho_lon = Float64[]
        ho_lat = Float64[]
        ho_t = Int[]
        ho_lvl = Int[]

        for s in 1:nsteps
            t = round(Int, s * dt)
            loc = DSim.step_position(model, loc, mstate, dt)
            push!(lons, r5(loc.lon))
            push!(lats, r5(loc.lat))
            push!(tss, t)

            ng = DSim.find_serving_gnb(topo, loc)
            if ng > 0 && ng != gnb
                nupf = topo.gnb_to_upf_map[ng]
                lvl = DSim.handover_level(topo, upf, nupf)
                push!(ho_lon, r5(loc.lon))
                push!(ho_lat, r5(loc.lat))
                push!(ho_t, t)
                push!(ho_lvl, lvl)
                gnb = ng
                upf = nupf
                nho += 1
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

function write_meta(path::String; country, operator, scale_factor, n_agents, duration, dt,
                    profile, nsteps, nedge, nho, trajectories_file, gnbs_file)
    meta = Dict(
        "country" => country,
        "country_label" => country_label(country),
        "operator" => operator,
        "operator_label" => operator_label(operator),
        "mobility_id" => profile["id"],
        "mobility_label" => profile["label"],
        "mobility_model" => profile["model"],
        "scale_factor" => scale_factor,
        "agents" => n_agents,
        "duration" => round(Int, duration),
        "dt" => dt,
        "speed_kmh" => profile["speed_kmh"],
        "nsteps" => nsteps,
        "edge_upfs" => nedge,
        "psas" => NUM_PSA,
        "handovers" => nho,
        "trajectories_file" => trajectories_file,
        "gnbs_file" => gnbs_file,
    )
    open(path, "w") do io
        JSON.print(io, meta, 2)
    end
end

function generate_bundle(toml_data, country::String, operator::String, scale_factor::Int,
                         profile, duration::Float64, dt::Float64, topo, nedge::Int)
    mkpath(OUTDIR)
    country_config = all_countries(toml_data)[country]

    population = Float64(country_config["population"])
    adoption = Float64(get(country_config, "mobile_adoption_rate", 0.82))
    n_agents = ceil(Int, population * adoption / scale_factor)
    nsteps = floor(Int, duration / dt)
    model = mobility_model(profile)

    stem = "$(country)-$(operator)-$(profile["id"])-s$(scale_factor)"
    gnb_file = "gnbs-$(country)-$(operator).json"
    traj_file = "trajectories-$(stem).json"
    meta_file = "meta-$(stem).json"

    gnb_path = joinpath(OUTDIR, gnb_file)
    if !isfile(gnb_path)
        write_gnbs(gnb_path, topo)
        println("Wrote $gnb_file ($(length(topo.gnb_locations)) sites)")
    else
        println("Keeping existing $gnb_file")
    end

    println("Generating $n_agents trajectories, $nsteps steps @ dt=$(dt)s ($(duration)s, $(profile["label"]), scale=$scale_factor)...")
    open(joinpath(OUTDIR, traj_file), "w") do io
        print(io, "[")
        nho = gen_trips(io, topo, model, n_agents, nsteps, dt)
        print(io, "]")
        write_meta(joinpath(OUTDIR, meta_file);
                   country, operator, scale_factor, n_agents, duration, dt, profile,
                   nsteps, nedge, nho, trajectories_file=traj_file, gnbs_file=gnb_file)
        println("Wrote $traj_file ($n_agents agents, $nho handovers)")
    end
end

function manifest_countries(toml_data)
    out = Any[]
    countries = all_countries(toml_data)
    for country in sort(collect(keys(countries)))
        cfg = countries[country]
        get(cfg, "enabled", false) || continue
        operators = Any[]
        for operator in sort(collect(keys(cfg["operators"])))
            op_cfg = cfg["operators"][operator]
            get(op_cfg, "enabled", false) || continue
            push!(operators, Dict("id" => operator, "label" => operator_label(operator)))
        end
        push!(out, Dict(
            "id" => country,
            "label" => country_label(country),
            "viewState" => get(COUNTRY_VIEWS, country, DEFAULT_VIEW),
            "operators" => operators,
        ))
    end
    return out
end

manifest_mobility_profiles() = [Dict(
    "id" => p["id"],
    "label" => p["label"],
    "short_label" => p["short_label"],
    "model" => p["model"],
    "speed_kmh" => p["speed_kmh"],
) for p in MOBILITY_PROFILES]

function write_manifest(toml_data)
    mkpath(OUTDIR)
    dataset_by_key = Dict{String,Any}()
    explicit_mobility_by_key = Dict{String,Bool}()
    if isdir(OUTDIR)
        for file in sort(readdir(OUTDIR))
            startswith(file, "meta-") || continue
            endswith(file, ".json") || continue
            meta_path = joinpath(OUTDIR, file)
            meta = JSON.parsefile(meta_path)
            country = String(meta["country"])
            operator = String(meta["operator"])
            explicit_mobility = haskey(meta, "mobility_id")
            mobility_id = String(get(meta, "mobility_id", "urban_50"))
            profile = mobility_profile(mobility_id)
            scale_factor = Int(meta["scale_factor"])
            traj_file = String(meta["trajectories_file"])
            gnb_file = String(meta["gnbs_file"])
            isfile(joinpath(OUTDIR, traj_file)) || continue
            isfile(joinpath(OUTDIR, gnb_file)) || continue

            key = "$(country)|$(operator)|$(mobility_id)|$(scale_factor)"
            dataset = Dict(
                "id" => "$(country)-$(operator)-$(mobility_id)-s$(scale_factor)",
                "country" => country,
                "country_label" => get(meta, "country_label", country_label(country)),
                "operator" => operator,
                "operator_label" => get(meta, "operator_label", operator_label(operator)),
                "mobility_id" => mobility_id,
                "mobility_label" => get(meta, "mobility_label", profile["label"]),
                "mobility_model" => get(meta, "mobility_model", profile["model"]),
                "scale_factor" => scale_factor,
                "agents" => Int(meta["agents"]),
                "duration" => Int(meta["duration"]),
                "dt" => Float64(meta["dt"]),
                "speed_kmh" => Float64(meta["speed_kmh"]),
                "handovers" => Int(meta["handovers"]),
                "edge_upfs" => Int(meta["edge_upfs"]),
                "psas" => Int(meta["psas"]),
                "files" => Dict(
                    "meta" => "data/$file",
                    "gnbs" => "data/$gnb_file",
                    "trajectories" => "data/$traj_file",
                ),
            )
            if !haskey(dataset_by_key, key) || (explicit_mobility && !explicit_mobility_by_key[key])
                dataset_by_key[key] = dataset
                explicit_mobility_by_key[key] = explicit_mobility
            end
        end
    end
    datasets = collect(values(dataset_by_key))
    sort!(datasets, by = d -> (d["country"], d["operator"], mobility_order(d["mobility_id"]), -d["scale_factor"]))

    scales = sort(unique(vcat(SCALE_PRESETS, [d["scale_factor"] for d in datasets])), rev=true)
    manifest = Dict(
        "version" => 1,
        "generated_at" => string(now()),
        "countries" => manifest_countries(toml_data),
        "mobility_profiles" => manifest_mobility_profiles(),
        "scales" => [Dict("scale_factor" => s, "label" => "1 agent = $s users") for s in scales],
        "datasets" => datasets,
    )
    open(joinpath(OUTDIR, "manifest.json"), "w") do io
        JSON.print(io, manifest, 2)
    end
    println("Updated $(joinpath(OUTDIR, "manifest.json")) ($(length(datasets)) bundle(s))")
end

function main()
    toml_data = TOML.parsefile(CONFIG_PATH)
    country_arg = length(ARGS) >= 1 ? ARGS[1] : DEFAULT_COUNTRY
    operator_arg = length(ARGS) >= 2 ? ARGS[2] : DEFAULT_OPERATOR
    scales = length(ARGS) >= 3 ? parse_scales(ARGS[3]) : DEFAULT_SCALES
    profiles = length(ARGS) >= 4 ? parse_mobility_profiles(ARGS[4]) : [mobility_profile(id) for id in DEFAULT_MOBILITY_IDS]
    duration = length(ARGS) >= 5 ? parse(Float64, ARGS[5]) : DEFAULT_DURATION
    dt = length(ARGS) >= 6 ? parse(Float64, ARGS[6]) : DEFAULT_DT

    for country in selected_countries(toml_data, country_arg)
        country_config = all_countries(toml_data)[country]
        for operator in selected_operators(country_config, operator_arg)
            topo, nedge = build_topology(country, operator, country_config, first(scales))
            for profile in profiles
                for scale_factor in scales
                    generate_bundle(toml_data, country, operator, scale_factor, profile, duration, dt, topo, nedge)
                end
            end
        end
    end
    write_manifest(toml_data)
end

main()
