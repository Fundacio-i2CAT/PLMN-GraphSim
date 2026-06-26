<div align="center">

# PLMN-GraphSim

**Research-grade Julia simulator for studying 5G and 6G-RUPA mobility, anchoring, and forwarding-state scalability over real PLMN topologies.**

[![Julia](https://img.shields.io/badge/Julia-1.11+-9558B2?style=flat-square&logo=julia&logoColor=white)](https://julialang.org/)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-2ea44f?style=flat-square)](https://fundacio-i2cat.github.io/PLMN-GraphSim/)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue?style=flat-square)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/Fundacio-i2CAT/PLMN-GraphSim?style=flat-square)](https://github.com/Fundacio-i2CAT/PLMN-GraphSim/commits/main)
[![Issues](https://img.shields.io/github/issues/Fundacio-i2CAT/PLMN-GraphSim?style=flat-square)](https://github.com/Fundacio-i2CAT/PLMN-GraphSim/issues)

</div>

---

PLMN-GraphSim models national-scale mobile-network deployments from geographic population and gNB datasets. It generates agents, places UPFs, simulates mobility and handovers, and reports how much forwarding and control-plane state different architectures need as users move.

The short version: use PLMN-GraphSim when you want to compare 5G-style anchoring against 6G-RUPA-inspired local mobility mechanisms without building a packet-level simulator first.

## Highlights

- Julia-based discrete-event simulation powered by `ConcurrentSim`.
- Real geography workflows for Spain and the USA using municipality, population, and OpenCellID-style gNB data.
- Agent generation driven by population distribution and configurable mobility models.
- UPF placement via gNB-density-aware clustering for single-tier and two-tier architectures.
- 5G and 6G-RUPA mobility accounting, including handover classification and forwarding-state metrics.
- Scenario outputs for topology plots, memory/state evolution, and paper-oriented analysis.
- Zensical documentation site published through GitHub Pages.

## What You Can Study

| Question | PLMN-GraphSim output |
| --- | --- |
| How much forwarding state does each UPF hold? | Per-UPF entry counts and memory estimates |
| How does mobility affect control-plane churn? | Handover classification and signaling-cost metrics |
| What changes between centralized and distributed UPF placement? | Single-tier and two-tier scenario comparisons |
| How do 5G and 6G-RUPA mobility mechanisms scale? | Side-by-side state and handover accounting |
| How does geography shape behavior? | Spain and USA topology and population-driven agent distributions |

## Quickstart

### Set Up Julia Environment

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Download Or Refresh Datasets

```bash
julia --project=. scripts/download_data.jl
```

Spain and USA sample datasets are included under `data/`. The download script is useful when starting from a lean checkout or refreshing external artifacts.

### Run The Interactive Simulator

```bash
julia --project=. main.jl
```

The entry point opens a small menu for running simulations or plotting topology graphs.

### Run A Scenario Script

```bash
julia --project=. run_minimal_topology.jl
julia --project=. run_synthetic_handover.jl
julia --project=. run_national_spain.jl
```

Use the smaller scripts first while validating an environment, then move to national or mobility-evaluation runs.

## Configuration

Simulation inputs live in `config.toml`. Countries, operators, simulation duration, scale factors, architecture choices, and mobility settings are configured there.

```toml
[countries.spain]
enabled = true
data_dir = "data/spain"
mcc = 214

  [countries.spain.operators]
  movistar = { id = 7, enabled = true }
```

Data follows this layout:

| Path | Purpose |
| --- | --- |
| `data/<country>/opencellid/<mcc>.csv` | gNB / cell-site locations |
| `data/<country>/municipalities.csv` | standardized municipality population and coordinates |
| `data/<country>/regions.geojson` | municipality or county boundaries |
| `data/processing_scripts/` | Python preprocessing tools for raw geographic datasets |

## Scenarios

| Scenario | Useful files |
| --- | --- |
| Minimal topology sanity checks | `run_minimal_topology.jl`, `run_synthetic_direct.jl` |
| Synthetic handover behavior | `run_synthetic_handover.jl`, `test/features/handover_classification.feature` |
| Spain national evaluation | `run_national_spain.jl`, `run_spain_focused.jl`, `run_spain_forced_handover.jl` |
| Mobility evaluation matrix | `run_mobility_eval.jl`, `run_mobility_eval_v3.jl` |
| Deployment sweep | `run_deployment_sweep.jl` |
| Browser visualization sample | `viz/index.html` |

## Documentation

- Documentation site: https://fundacio-i2cat.github.io/PLMN-GraphSim/
- Quickstart: https://fundacio-i2cat.github.io/PLMN-GraphSim/quickstart/
- Simulator internals: https://fundacio-i2cat.github.io/PLMN-GraphSim/simulation-details/how-simulator-works/
- Mobility models: https://fundacio-i2cat.github.io/PLMN-GraphSim/simulation-details/mobility-models/

Build the documentation locally:

```bash
python3 -m venv docs/.venv
docs/.venv/bin/pip install -r docs/requirements.txt
docs/.venv/bin/zensical build
```

Serve it while editing:

```bash
docs/.venv/bin/zensical serve
```

## Development

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. test/runtests.jl
julia --project=. test/qa.jl
```

Generate coverage HTML when `lcov` is available:

```bash
julia --project=. scripts/post-simulation-analysis/generate_coverage_manual.jl
genhtml lcov.info --output-directory coverage_html
python3 -m http.server -d coverage_html
```

Then open `http://localhost:8000`.

## Project Scope

PLMN-GraphSim focuses on topology, mobility, anchoring, and forwarding-state scalability. It is not a packet-level simulator and does not model PHY behavior, queues, TCP/IP dynamics, or radio scheduling.

For packet-level studies, use PLMN-GraphSim to generate topology and state artifacts, then connect those outputs to packet simulators such as NS-3.

## License

PLMN-GraphSim is released under the [AGPL-3.0 license](LICENSE).

<div align="center">

Built at [Fundacio i2CAT](https://i2cat.net/).

</div>
