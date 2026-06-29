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
