using Downloads

# TODO: Create a release on GitHub (e.g., tag v0.1.0) and upload 'data.zip' to it.
# Then, copy the link to the uploaded asset and paste it below.
# FOR BLIND REVIEW: Use a Figshare/Zenodo anonymous link here.
const DATA_URL = "https://figshare.com/s/c116f5a9c2e0f0a77ceb"
const DATA_DIR = joinpath(@__DIR__, "..", "data")

function download_and_extract()
    if !isdir(DATA_DIR)
        mkpath(DATA_DIR)
    end

    zip_path = joinpath(DATA_DIR, "data.zip")
    
    println("Downloading data from $DATA_URL...")
    try
        Downloads.download(DATA_URL, zip_path)
        println("Download complete.")
        
        println("Extracting data...")
        # Using system unzip command (works on Linux/macOS)
        # For Windows, or if unzip is missing, you might need a pure Julia solution like ZipFile.jl
        # The -o flag overwrites existing files without prompting
        run(`unzip -o $zip_path -d $DATA_DIR`)
        
        println("Extraction complete.")
        rm(zip_path)
        println("Cleaned up zip file.")
        
    catch e
        println("Error: $e")
        println("Please ensure 'unzip' is installed or manually download and extract the data to $DATA_DIR")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    download_and_extract()
end
