# Quickstart Guide

## Configuration

The simulation is configured via `config.toml`. You can define simulation parameters (duration, scale factor) and select which countries and operators to simulate. The configuration file is pretty self-explanatory, and the sample one provided is ready to be used.

## Data Files

US and Spain datasets are ready to quickly get started, so you can just go either for the US setup or the Spain setup.

For more information about the  datasets, check the Datasets section.

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
1. Run Full Simulation
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
