module DataLoading

using CSV
using DataFrames
using Clustering
using HTTP
using JSON
using JSON3
using GeoJSON
using Graphs
using MetaGraphsNext
using ..Types
using Logging

export load_and_deploy_network, load_and_cluster, load_municipalities

# INE API Base URL
const INE_BASE_URL = "https://servicios.ine.es/wstempus/js/es"

include("DataLoading/Municipalities.jl")
include("DataLoading/Graph.jl")
include("DataLoading/Loader.jl")

end
