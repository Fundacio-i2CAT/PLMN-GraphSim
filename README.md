# PLMN-GraphSim

## Prerequisites & Setup

FIrst, install Julia (version 1.11 recommneded).

```bash
curl -fsSL https://install.julialang.org | sh
```

Now let's  set up the simulation environment and download the necessary datasets:

Instantiate Julia Environment:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

It will take a few minutes to download and compile all dependencies.

Then download datasets. This project uses large geospatial datasets that have been pre-processed by the scripts in `data/processing_scripts/`. To simplify the setup, we provide a script to download the pre-processed datasets directly.

```bash
julia scripts/download_data.jl
```

*Note: For the review process, this script fetches the anonymized dataset from Figshare.*

Figshare sometimes does not allow direct downloads via command line tools. If you encounter issues, please download the dataset manually from [this link](https://figshare.com/articles/dataset/PLMN-GraphSim_Datasets/23315328) and extract it in `PLMN-GraphSim/data/`:

```bash
unzip -o data.zip -d PLMN-GraphSim/data/
```

Now you are all set to run the simulator. To run it just do:

```bash
$ julia --project=. main.jl

  Activating project at `~/PLMN-GraphSim`
==========================================
   6G-RUPA DES Simulation Framework
==========================================
Select an action to run:
1. Run Full Simulation (Centralized vs Distributed)
2. Plot Network Topology
q. Quit
==========================================
```

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
   PLMN-GraphSim DES Simulation Framework       
==========================================
Select an action to run:
1. Run Full Simulation (Centralized vs Distributed)
2. Plot Network Topology
q. Quit
==========================================
Enter choice: 
```

Select option `1` to run the full simulation, or option `2` to plot the network topology graphs.

### Plotting Functionality

To keep the core simulation lightweight, plotting functionality is provided via a **Package Extension**. 

*   The core simulation does **not** require `Plots.jl`.
*   To enable plotting (e.g., for Option 2 in the menu or `scripts/plot_topology.jl`), you must have `Plots` installed in your environment.

**1. Add the Plots package:**

```bash
julia --project=. -e 'using Pkg; Pkg.add("Plots")'
```

**2. Run the plotting script:**

```bash
julia --project=. scripts/plot_topology.jl
```

Or select Option 2 in the main menu.

If you try to plot without `Plots` installed, you will see a warning message.

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

