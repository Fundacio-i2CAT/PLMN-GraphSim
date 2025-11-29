# DesJulia6gRupa

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

## Data Files

* **`data/214.csv`**: Contains **Cell Tower (gNB) locations** for Spain (MCC 214).
  * *Source*: [OpenCellID](https://opencellid.org/).
* **`data/municipalities_coordinates.csv`**: Essential for **population data** (used to distribute agents realistically) and municipality centroids.
  * *Source*: CNIG (Centro Nacional de Información Geográfica) via [Datos Abiertos del CNIG](https://centrodedescargas.cnig.es/CentroDescargas/nomenclator-geografico-municipios-entidades-poblacion).
* **`data/esri_municipios.geojson`**: Essential for **geometric boundaries** (polygons), used to verify if agents are located within valid municipality borders.
  * *Source*: [IGN (Instituto Geográfico Nacional)](https://opendata.esri.es/datasets/municipios-ign).

Both municipality files are required because the GeoJSON lacks population statistics, while the CSV lacks the polygon shapes needed for spatial containment checks.
