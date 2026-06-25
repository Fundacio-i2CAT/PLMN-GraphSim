using ..Types

"""
    GnbGrid

Uniform grid (bucket) spatial index over gNB locations for fast nearest-gNB
queries. Brute-force `find_serving_gnb` is O(#gNB) per call; at national scale
(46k–113k gNBs × tens of thousands of mobile agents × hundreds of ticks) that is
the simulation bottleneck. The grid makes a query ~O(1) amortized by bucketing
gNBs into cells and searching expanding rings around the query point.

Coordinates are treated as planar (lat, lon); for nearest-neighbour *ranking*
within a country this is fine (same approximation `find_serving_gnb` already uses).
"""
struct GnbGrid
    cell::Float64          # cell size in degrees
    lat0::Float64          # grid origin (min lat)
    lon0::Float64          # grid origin (min lon)
    buckets::Dict{Tuple{Int,Int},Vector{Int}}  # (row,col) -> gNB indices
end

@inline _cellidx(g::GnbGrid, lat, lon) =
    (floor(Int, (lat - g.lat0) / g.cell), floor(Int, (lon - g.lon0) / g.cell))

# Per-topology grid cache, keyed by identity of the gNB-location vector. The grid
# is built once on first query and reused for the rest of a run. ConcurrentSim is
# cooperative single-threaded, so no locking is needed.
const _GRID_CACHE = IdDict{Any,Any}()

function get_gnb_grid(gnb_locations::Vector{GeoPoint})
    g = get(_GRID_CACHE, gnb_locations, nothing)
    g === nothing || return g::GnbGrid
    g = build_gnb_grid(gnb_locations)
    _GRID_CACHE[gnb_locations] = g
    return g
end

"""
    build_gnb_grid(gnb_locations; target_per_cell=2.0)

Build a `GnbGrid` sized so each cell holds ~`target_per_cell` gNBs on average.
"""
function build_gnb_grid(gnb_locations::Vector{GeoPoint}; target_per_cell::Float64=2.0)
    n = length(gnb_locations)
    lats = (p.lat for p in gnb_locations); lons = (p.lon for p in gnb_locations)
    lat0, lat1 = minimum(lats), maximum(lats)
    lon0, lon1 = minimum(lons), maximum(lons)
    area = max(lat1 - lat0, 1e-6) * max(lon1 - lon0, 1e-6)
    cell = sqrt(area * target_per_cell / max(n, 1))
    cell = max(cell, 1e-4)
    buckets = Dict{Tuple{Int,Int},Vector{Int}}()
    grid = GnbGrid(cell, lat0, lon0, buckets)
    for (i, p) in enumerate(gnb_locations)
        key = _cellidx(grid, p.lat, p.lon)
        push!(get!(buckets, key, Int[]), i)
    end
    return grid
end

"""
    nearest_gnb(grid, gnb_locations, loc) -> Int

Index of the gNB nearest to `loc` (0 if none). Searches expanding square rings
around the query cell, stopping once no unexplored cell can beat the current best
(the ring's minimum possible distance exceeds the best found). Returns the same
result as brute force.
"""
function nearest_gnb(grid::GnbGrid, gnb_locations::Vector{GeoPoint}, loc::GeoPoint)
    isempty(gnb_locations) && return 0
    crow, ccol = _cellidx(grid, loc.lat, loc.lon)
    best = 0
    bestd2 = Inf
    ring = 0
    while true
        # scan the square ring at Chebyshev distance `ring` from the center cell
        for dr in -ring:ring, dc in -ring:ring
            (max(abs(dr), abs(dc)) == ring) || continue   # ring perimeter only
            cell = get(grid.buckets, (crow + dr, ccol + dc), nothing)
            cell === nothing && continue
            for idx in cell
                p = gnb_locations[idx]
                d2 = (p.lat - loc.lat)^2 + (p.lon - loc.lon)^2
                if d2 < bestd2
                    bestd2 = d2; best = idx
                end
            end
        end
        # Once we have a candidate, the true nearest can only lie within distance
        # sqrt(bestd2). Any ring whose nearest edge is farther than that cannot
        # improve it: stop when ring*cell exceeds sqrt(bestd2).
        if best != 0 && (ring * grid.cell) > sqrt(bestd2)
            break
        end
        ring += 1
        # safety: if we have searched well beyond the populated extent, stop
        if ring > 4 && best != 0
            # extra guard handled by the distance test above; this prevents
            # pathological infinite growth on degenerate inputs
        end
        if ring > 100_000
            break
        end
    end
    return best
end
