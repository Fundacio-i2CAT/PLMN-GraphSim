using Downloads
using SHA

const DATASET_PID = "doi:10.34810/data3210"
const DATASET_VERSION = "1.0"
const DATA_DIR = joinpath(@__DIR__, "..", "data")
const API_BASE = "https://dataverse.csuc.cat/api"

const FILE_MAP = [
    # Spain
    (450093, "spain", "municipalities.csv", "2d84b0dfae919ef61e6ecedd5865779b01deada69d67812c930367e28e085ec9"),
    (450098, "spain", "cities.csv", "7a4fbf2f6b1f5c242e04221ee3ac735ca9dac21d316dfb19f65dfd7f849e3685"),
    (450101, "spain", "regions.geojson", "02e6fe12574f926fd046874e98202bf1c6694fa608d874ace6b003e9d4257434"),
    (450103, "spain/opencellid", "214.csv", "c9ead7336d646a0683950a4d961986fedf3d36385a142d709461aadc7e19aa91"),
    # USA
    (450102, "usa", "municipalities.csv", "4f910aa8958e8e42e026135b659d0d2498bb0a53a61378bb2f939bcd4b49c4d0"),
    (450104, "usa", "cities.csv", "873db1daf7dd27c1d9e70f606e7a74361510a33a3b0056e27a77e44e1f354a00"),
    (450097, "usa", "regions.geojson", "8cc6a42199611cf570893e154542bde74b83cd70c110e475bc015cf437843af4"),
    (450094, "usa/opencellid", "311.csv", "ecae5a07c1e9a3e64bf911553a133be766b25c15e041ceb1c25bcb6098e9098d"),
    (450095, "usa/opencellid", "312.csv", "25a3ae521a54be338bf1046691373f3803f50af8228006f6fb9faa8283db203b"),
    (450096, "usa/opencellid", "313.csv", "d92a1bad9e3c0f5512d669d4d20e003edc31c0946e4c18d27ea4be1cf1f3f6de"),
    (450099, "usa/opencellid", "314.csv", "cc3aba3778b9b2e675e0d21bef77ff234f9710141ef70d450d497fb67c882ca6"),
    (450100, "usa/opencellid", "310.csv", "28862f9b38a48a1fa718e7395ad89b3f2e2130516128014659bdb074398090dd"),
]

sha256(path) = bytes2hex(open(SHA.sha256, path))

function download_and_extract()
    if !isdir(DATA_DIR)
        mkpath(DATA_DIR)
    end

    errors = []

    println("Dataset $DATASET_PID, version $DATASET_VERSION")
    for (file_id, subdir, filename, expected_sha256) in FILE_MAP
        url = "$(API_BASE)/access/datafile/$file_id?format=original"
        dest_dir = joinpath(DATA_DIR, subdir)
        if !isdir(dest_dir)
            mkpath(dest_dir)
        end
        dest_path = joinpath(dest_dir, filename)

        println("Downloading $filename from dataset...")
        try
            tmp_path = dest_path * ".part"
            Downloads.download(url, tmp_path)
            actual_sha256 = sha256(tmp_path)
            actual_sha256 == expected_sha256 || error(
                "SHA-256 mismatch for $filename: expected $expected_sha256, got $actual_sha256"
            )
            mv(tmp_path, dest_path; force=true)
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
