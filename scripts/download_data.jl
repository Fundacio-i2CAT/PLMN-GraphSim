using Downloads
using JSON3

const DATASET_PID = "doi:10.34810/data3210"
const DATA_DIR = joinpath(@__DIR__, "..", "data")
const API_BASE = "https://dataverse.csuc.cat/api"

const FILE_MAP = [
    # Spain
    ("$(API_BASE)/access/datafile/450093", "spain", "municipalities.csv"),
    ("$(API_BASE)/access/datafile/450098", "spain", "cities.csv"),
    ("$(API_BASE)/access/datafile/450101", "spain", "regions.geojson"),
    ("$(API_BASE)/access/datafile/450103", "spain/opencellid", "214.csv"),
    # USA
    ("$(API_BASE)/access/datafile/450102", "usa", "municipalities.csv"),
    ("$(API_BASE)/access/datafile/450104", "usa", "cities.csv"),
    ("$(API_BASE)/access/datafile/450097", "usa", "regions.geojson"),
    ("$(API_BASE)/access/datafile/450094", "usa/opencellid", "311.csv"),
    ("$(API_BASE)/access/datafile/450095", "usa/opencellid", "312.csv"),
    ("$(API_BASE)/access/datafile/450096", "usa/opencellid", "313.csv"),
    ("$(API_BASE)/access/datafile/450099", "usa/opencellid", "314.csv"),
    ("$(API_BASE)/access/datafile/450100", "usa/opencellid", "310.csv"),
]

function download_and_extract()
    if !isdir(DATA_DIR)
        mkpath(DATA_DIR)
    end

    errors = []

    for (url, subdir, filename) in FILE_MAP
        dest_dir = joinpath(DATA_DIR, subdir)
        if !isdir(dest_dir)
            mkpath(dest_dir)
        end
        dest_path = joinpath(dest_dir, filename)

        println("Downloading $filename from dataset...")
        try
            Downloads.download(url, dest_path)
            println("  -> $dest_path")
        catch e
            msg = "Failed to download $filename: $e"
            println(msg)
            push!(errors, msg)
        end
    end

    if isempty(errors)
        println("\nAll files downloaded successfully.")
    else
        println("\nSome files failed to download:")
        for err in errors
            println("  $err")
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    download_and_extract()
end
