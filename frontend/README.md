# Static Mobility Frontend

This directory is frontend-only: HTML, CSS, JavaScript, and precomputed JSON assets.
It does not run Julia and does not need a backend.

## Precompute Data

Generate one bundle:

```bash
julia --project=. gen_trajectories.jl usa verizon 100000 urban_50 1200 2
```

Generate several country/operator/scale bundles:

```bash
julia --project=. gen_trajectories.jl all all 100000,50000,25000 all 1200 2
```

Lower scale factor means more simulated agents and heavier browser load. For US,
start coarse (`100000` or `50000`) before trying precise scales.

Mobility profiles match the paper evaluation:

- `pedestrian_5`: Random Waypoint, 5 km/h
- `urban_50`: Random Waypoint, 50 km/h
- `highway_120`: Gauss-Markov, 120 km/h

The script writes generated files into `frontend/data/` and updates
`frontend/data/manifest.json`. Generated bundle files are git-ignored; the manifest
is tracked.

## Serve Static

```bash
python3 -m http.server 8000
```

Open `http://localhost:8000/frontend/`.

## Current Precomputed Matrix

Tracked `frontend/data/manifest.json` references these generated bundle families:

| Topology | Operator | Scales |
| --- | --- | --- |
| Spain | Movistar | `100000`, `50000`, `25000`, `10000`, `5000` |
| USA | Verizon OpenCellID | `100000`, `50000`, `25000`, `10000` |
| USA ASR | FCC ASR macro structures | `100000`, `50000`, `25000`, `10000` |

Each family has all three paper mobility profiles. The generated JSON assets are
ignored by git; keep them beside the manifest when deploying the static frontend.

USA ASR is operator-agnostic and should be interpreted as a macro-structure
sensitivity check, not a real Verizon-equivalent network.
