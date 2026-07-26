#!/usr/bin/env julia
# Satellite ground-track export for the browser frontend (§7.5.2 phase A).
#   julia --project main.jl ntn_tracks                       # starlink over spain
#   julia --project main.jl ntn_tracks starlink spain 1200 5
#   julia --project main.jl ntn_tracks oneweb portugal
#
# Writes frontend/data/ntn-<constellation>-<country>.json: ground tracks (sampled
# sub-satellite points) for every satellite whose track crosses the country's
# bounding box (± footprint margin) during the sim window, plus the nominal
# coverage-footprint radius for the min-elevation cone. Purely deterministic
# (SGP4 on the LEOPath TLE sets) — independent of agent scale, so one file per
# (constellation, country) serves every bundle. The frontend shows a "satellites"
# toggle when the file exists.

using DesJulia6gRupa
import DesJulia6gRupa.Simulation as DSim
import JSON3

const CONSTELLATION = lowercase(get(ARGS, 1, "starlink"))
const COUNTRY = lowercase(get(ARGS, 2, "spain"))
const DURATION = parse(Float64, get(ARGS, 3, "1200"))
const DT = parse(Float64, get(ARGS, 4, "5"))
const MIN_ELEV = 25.0

const TLE_FILES = Dict(
    "starlink" => "tles_starlink_550_sgp.txt",
    "oneweb"   => "tles_oneweb_synth.txt",
    "kuiper"   => "tles_kuiper_synth.txt",
    "telesat"  => "tles_telesat_synth.txt",
)

root = pkgdir(DesJulia6gRupa)
tle_path = joinpath(root, "data", "ntn", TLE_FILES[CONSTELLATION])
isfile(tle_path) || error("no TLE file $tle_path")

# Country bbox from any existing frontend gNB bundle (they carry [lon, lat] pairs).
data_dir = get(ENV, "FRONTEND_DATA_DIR", joinpath(root, "frontend", "data"))
gnb_files = filter(f -> startswith(f, "gnbs-$COUNTRY-") || f == "gnbs-$COUNTRY.json",
                   isdir(data_dir) ? readdir(data_dir) : String[])
isempty(gnb_files) && error("no gnbs-$COUNTRY-*.json under $data_dir — export a country bundle first")
pts = JSON3.read(read(joinpath(data_dir, gnb_files[1]), String))
lons = [p[1] for p in pts]; lats = [p[2] for p in pts]

c = DSim.load_constellation(tle_path; operator_id = 9, min_elevation_deg = MIN_ELEV)
n = DSim.n_satellites(c)

# Nominal footprint ground radius for the min-elevation cone at the shell altitude:
# central angle γ = acos(R/(R+h)·cos(el)) − el.
DSim.positions_at!(c, 0.0)
alt = sum(c.cache_alt) / n
R = DSim.EARTH_RADIUS_KM
el = deg2rad(MIN_ELEV)
γ = acos(R / (R + alt) * cos(el)) - el
footprint_km = R * γ

margin = rad2deg(γ) + 3.0
bbox = (minimum(lats) - margin, maximum(lats) + margin,
        minimum(lons) - margin, maximum(lons) + margin)
println("$CONSTELLATION: $n sats, shell ≈$(round(Int, alt)) km, footprint ≈$(round(Int, footprint_km)) km")
println("$COUNTRY bbox ±margin: lat $(round.(bbox[1:2], digits=1)) lon $(round.(bbox[3:4], digits=1))")

times = collect(0.0:DT:DURATION)
lat_tracks = [Float64[] for _ in 1:n]
lon_tracks = [Float64[] for _ in 1:n]
for t in times
    DSim.positions_at!(c, t)
    for i in 1:n
        push!(lat_tracks[i], c.cache_lat[i])
        push!(lon_tracks[i], c.cache_lon[i])
    end
end

inbox(la, lo) = bbox[1] <= la <= bbox[2] && bbox[3] <= lo <= bbox[4]
sats = []
for i in 1:n
    any(inbox(lat_tracks[i][k], lon_tracks[i][k]) for k in eachindex(times)) || continue
    push!(sats, Dict(
        "id" => i,
        "path" => [[round(lon_tracks[i][k], digits=4), round(lat_tracks[i][k], digits=4)]
                   for k in eachindex(times)],
        "ts" => times,
    ))
end

out = Dict(
    "constellation" => CONSTELLATION,
    "country" => COUNTRY,
    "min_elevation_deg" => MIN_ELEV,
    "footprint_km" => round(footprint_km, digits=1),
    "shell_alt_km" => round(alt, digits=1),
    "duration" => DURATION,
    "dt" => DT,
    "total_sats" => n,
    "bbox" => Dict("lat_min" => bbox[1], "lat_max" => bbox[2],
                   "lon_min" => bbox[3], "lon_max" => bbox[4]),
    "sats" => sats,
)
outfile = joinpath(data_dir, "ntn-$CONSTELLATION-$COUNTRY.json")
open(outfile, "w") do io
    JSON3.write(io, out)
end
println("wrote $(length(sats))/$n visible tracks → $outfile ($(round(filesize(outfile)/1e6, digits=1)) MB)")
