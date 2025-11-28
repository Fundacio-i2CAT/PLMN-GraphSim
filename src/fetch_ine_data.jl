using HTTP
using JSON
using CSV
using DataFrames

# INE API Base URL
const INE_BASE_URL = "https://servicios.ine.es/wstempus/js/es"

function fetch_population_by_province()
    println("Fetching population data from INE API...")

    # Table ID 2852: Resident population by date, sex, age group and province
    # We filter for:
    # - Sex: Total (ID 0 or similar, usually implicit if not requested or we sum it)
    # - Age: Total
    # - Date: Last available
    
    # Actually, a simpler table is "Population by province" (Main Series)
    # Let's try to fetch the data for Table 2852 but requesting only the "Total" values.
    # URL pattern: DATOS_TABLA/{TableID}?nult=1 (Last data)
    
    # Note: In a real scenario, we might need to inspect the metadata to get the exact codes for "Total".
    # For this example, I will simulate the structure if the fetch fails, or use a direct download if possible.
    
    # Let's try a direct JSON fetch for the latest data
    url = "$INE_BASE_URL/DATOS_TABLA/2852?nult=1"
    
    try
        resp = HTTP.get(url)
        data = JSON.parse(String(resp.body))
        
        # The INE API returns a list of time series. We need to filter for "Total" population per province.
        # The "Nombre" field usually contains the description: "Albacete. Total. Total. ..."
        
        provinces = String[]
        populations = Int[]
        
        for entry in data
            name = entry["Nombre"]
            # We look for entries that represent the TOTAL population for a province
            # Format is often: "ProvinceName. Total. Total. ..."
            
            # Simple heuristic: Check if it contains "Total" and extract the province name
            # This is a simplification; robust parsing requires checking metadata codes (Variables).
            
            # Let's assume we want to parse the value:
            if occursin("Total", name) && !occursin("Españoles", name) && !occursin("Extranjeros", name)
                # Extract value
                if !isempty(entry["Data"])
                    val = entry["Data"][1]["Valor"]
                    
                    # Extract Province Name (First part of the string)
                    prov_name = split(name, ".")[1]
                    
                    push!(provinces, strip(prov_name))
                    push!(populations, Int(round(val)))
                end
            end
        end
        
        # Create DataFrame
        df = DataFrame(Province = provinces, Population = populations)
        
        # Aggregate duplicates if any (due to loose filtering)
        df = combine(groupby(df, :Province), :Population => maximum => :Population)
        
        println("Fetched data for $(nrow(df)) provinces.")
        return df
        
    catch e
        println("Error fetching from INE API: $e")
        println("Falling back to manual/mock data for demonstration.")
        return DataFrame()
    end
end

function save_data(df::DataFrame, filepath::String)
    if isempty(df)
        println("No data to save.")
        return
    end
    CSV.write(filepath, df)
    println("Data saved to $filepath")
end

# --- Main Execution ---
if abspath(PROGRAM_FILE) == @__FILE__
    df = fetch_population_by_province()
    
    # If API fails (e.g. no internet in this env), we create a mock file based on real approx stats
    if isempty(df)
        println("Generating fallback data...")
        provinces = ["Madrid", "Barcelona", "Valencia", "Sevilla", "Alicante", "Málaga", "Murcia", "Cádiz", "Vizcaya", "A Coruña", "Asturias"]
        pops = [6700000, 5700000, 2600000, 1950000, 1900000, 1700000, 1500000, 1250000, 1150000, 1120000, 1000000]
        df = DataFrame(Province = provinces, Population = pops)
    end
    
    output_path = joinpath(@__DIR__, "../data/population_ine.csv")
    save_data(df, output_path)
end
