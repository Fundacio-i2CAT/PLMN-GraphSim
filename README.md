# DesJulia6gRupa

## Configuration

The simulation is configured via `config.toml`. You can define simulation parameters (duration, scale factor) and select which countries and operators to simulate.

```toml
[countries.spain]
enabled = true
data_dir = "data/spain"
mcc = 214

    [countries.spain.operators]
    vodafone = { id = 1, enabled = true }
```

## Data Files

Data is organized by country in the `data/` directory (e.g., `data/spain/`, `data/usa/`).

* **`data/<country>/opencellid/<mcc>.csv`**: Cell Tower (gNB) locations.
* **`data/<country>/municipalities.csv`**: Standardized municipality data (id, name, population, lat, lon).
* **`data/<country>/regions.geojson`**: Geometric boundaries for municipalities.

Python scripts for downloading and standardizing data are located in the `data/processing_scripts/` directory. See `data/README.md` for details.

## Run Simulator

Run the main simulation entry point:

```bash
julia --project=. main.jl
```

That will execute a very simple interactive menu:

```source
   6G-RUPA DES Simulation Framework       
==========================================
Select an action to run:
1. Run Full Simulation (Centralized vs Distributed)
2. Plot Network Topology
q. Quit
==========================================
Enter choice: 
```

Select option `1` to run the full simulation, or option `2` to plot the network topology graphs.

## Run Tests

Execute the test suite:

```bash
julia --project=. test/runtests.jl
```

## Test Coverage

1. Generate coverage data:

   ```bash
   julia scripts/generate_coverage_manual.jl
   ```

2. View results as HTML (requires `lcov`. In linux you can install it via `sudo apt install lcov`):

   ```bash
   genhtml lcov.info --output-directory coverage_html
   ```

   Then you need to serve the files, e.g., via python:

   ```bash
   python3 -m http.server -d coverage_html
   ```

   Then open http://localhost:8000

