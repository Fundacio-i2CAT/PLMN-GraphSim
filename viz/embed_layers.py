#!/usr/bin/env python3
"""Embed the exported layer-stack JSONs into the self-contained inspector page.

Usage: python3 viz/embed_layers.py
Reads  viz/layers.template.html + viz/data/layers_{flat,hierarchy}.json
Writes viz/layers.html  (open directly in a browser; no server needed)
Re-run after `julia --project runs/layers_viz.jl` to refresh the snapshot.
"""
import json
import pathlib

root = pathlib.Path(__file__).parent
template = (root / "layers.template.html").read_text()
flat = json.dumps(json.load(open(root / "data" / "layers_flat.json")), separators=(",", ":"))
hier = json.dumps(json.load(open(root / "data" / "layers_hierarchy.json")), separators=(",", ":"))
out = template.replace("__FLAT__", flat).replace("__HIER__", hier)
(root / "layers.html").write_text(out)
print(f"wrote {root / 'layers.html'} ({len(out) // 1024} KB)")
