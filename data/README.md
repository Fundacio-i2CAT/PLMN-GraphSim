# Data Processing Scripts

This directory contains Python scripts to process and standardize raw data (e.g., from INE, US Census, OpenCellID) into the format required by the Julia simulation.

The scripts are located in the `processing_scripts/` subdirectory.

## Setup

To run these scripts, it is recommended to create a Python virtual environment within the `processing_scripts` directory to manage dependencies.

1.  **Navigate to the scripts directory:**
    ```bash
    cd processing_scripts
    ```

2.  **Create a virtual environment:**
    ```bash
    python3 -m venv .venv
    ```

3.  **Activate the environment:**
    ```bash
    source .venv/bin/activate
    ```

4.  **Install dependencies:**
    ```bash
    pip install -r requirements.txt
    ```

## Running the Scripts

Once the environment is active and you are in the `processing_scripts` directory, you can run the scripts to process the data.

### USA Data
1.  **Process Raw Census Data:**
    Downloads/reads raw Shapefiles and CSVs from `../usa/agent-unprocessed-raw-datasets/` and generates intermediate files.
    ```bash
    python process_usa_data.py
    ```

2.  **Process Cities:**
    Filters and formats the US cities database.
    ```bash
    python process_usa_cities.py
    ```

3.  **Standardize for Simulation:**
    Converts the processed files into the final `municipalities.csv` and `regions.geojson` formats expected by the simulation.
    ```bash
    python standardize_usa.py
    ```

### Spain Data
1.  **Standardize for Simulation:**
    Converts the raw Spanish data (from `../spain/agent-unprocessed-raw-datasets/`) into the final standard format.
    ```bash
    python standardize_spain.py
    ```
