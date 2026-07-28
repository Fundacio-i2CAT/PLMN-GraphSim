# Shared test fixtures: the single source of truth for σ constants and the mock
# topology builders every test file rewires. If the paper's derivation changes a
# constant, change it HERE and the whole suite follows (this is why the σ literals
# used to drift — 1180/400 lingered in five files). Mirrors src/Simulation/
# {Handover,Layers,NTN}.jl; grounded in infocom-mobility-paper/notes/* and the
# living spec test/features/handover_classification.feature.
#
# Included once by runtests.jl; each test file guards with `isdefined` so it can
# still be run standalone (`julia --project -e 'include("test/FooTests.jl")'`).

module TestFixtures

using DesJulia6gRupa
using DesJulia6gRupa.Types
using DesJulia6gRupa.DataLoading
using Graphs
using MetaGraphsNext

export SIGMA_XN, SIGMA_N2, SIGMA_RUPA,
       SIGMA_ROAM_5G_REEST, SIGMA_ROAM_5G_IDEAL, SIGMA_ROAM_RUPA,
       SIGMA_NTN_SATHO_5G, SIGMA_NTN_SATHO_RUPA
export mock_graph, single_tier_topology, two_psa_topology, op_field

# --- σ constants (per event, bytes) ---
const SIGMA_XN             = 600     # intra-domain, same anchor (5G Xn)
const SIGMA_N2             = 1150    # inter-domain, anchor preserved (5G N2)
const SIGMA_RUPA           = 200     # 6G-RUPA renumber — FLAT: intra == inter
const SIGMA_ROAM_5G_REEST  = 3250    # crossing, :reestablish (+ break + acct reloc)
const SIGMA_ROAM_5G_IDEAL  = 1300    # crossing, :ideal_ho (no break)
const SIGMA_ROAM_RUPA      = 450     # crossing entry (then SIGMA_RUPA per move)
const SIGMA_NTN_SATHO_5G   = 1150    # satellite switch N2 endpoint; Xn endpoint = SIGMA_XN
const SIGMA_NTN_SATHO_RUPA = 200

# --- topology builders ---
mock_graph() = MetaGraph(Graph(), label_type = Tuple{Symbol,Int},
                         vertex_data_type = GeoPoint, edge_data_type = Float64)

"Single-tier: n gNBs 1:1 with n edge UPFs, no PSA layer."
function single_tier_topology(n::Int)
    locs = [GeoPoint(0.0, 0.1 * (i - 1)) for i in 1:n]
    NetworkTopology(locs, copy(locs), collect(1:n), GeoPoint[], Int[],
        Municipality[], Dict{String,Vector{Int}}(), Float64[], mock_graph())
end

"""
Two-tier taxonomy fixture: 4 gNBs, 3 edge UPFs, 2 PSAs.
edge 1,2 → PSA 1 ; edge 3 → PSA 2. Exercises L1 (same edge), L2 (diff edge, same
PSA), and a PSA-region crossing (edge 2 → 3) that stays L2 under SSC mode 1.
"""
function two_psa_topology()
    gnb  = [GeoPoint(0.0, 0.0), GeoPoint(0.1, 0.1), GeoPoint(0.2, 0.2), GeoPoint(0.3, 0.3)]
    edge = [GeoPoint(0.0, 0.0), GeoPoint(0.1, 0.1), GeoPoint(0.3, 0.3)]
    psa  = [GeoPoint(0.05, 0.05), GeoPoint(0.3, 0.3)]
    NetworkTopology(gnb, edge, [1, 2, 3, 3], psa, [1, 1, 2],
        Municipality[], Dict{String,Vector{Int}}(), Float64[], mock_graph())
end

"One operator field: n gNBs (1:1 edge UPFs) → 1 PSA, one municipality (population `pop`)."
function op_field(n::Int, lon0::Float64, pop::Int, code::String)
    NetworkTopology(
        [GeoPoint(40.0, lon0 - (i - 1)) for i in 1:n],
        [GeoPoint(40.0, lon0 - (i - 1)) for i in 1:n],
        collect(1:n),
        [GeoPoint(40.0, lon0)], fill(1, n),
        [Municipality(code, code, pop, GeoPoint(40.0, lon0), 0.0, nothing)],
        Dict{String,Vector{Int}}(), [1.0], mock_graph())
end

end # module
