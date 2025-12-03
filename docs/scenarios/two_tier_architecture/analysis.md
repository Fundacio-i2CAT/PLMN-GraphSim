# Analysis

This section details the analysis of the simulation results for the Two-Tier architecture.

## Output Files

The simulation generates the following result files in the `results/` directory:

*   `simulation_results_<Operator>_<Scenario>.csv`: Aggregated metrics.
*   `raw_upf_state_<Operator>_<Scenario>.csv`: Time-series data of UPF loads.
*   `evolution_5g_mb_<Operator>_<Scenario>.csv`: Data volume evolution.
*   `evolution_5g_entries_<Operator>_<Scenario>.csv`: Session count evolution.

## Key Metrics

In the Two-Tier architecture, we analyze:

1.  **Edge UPF Load**: How much traffic is handled locally by the UL-CLs.
2.  **Centralized UPF Load**: The aggregated traffic reaching the PSAs.
3.  **Backhaul Usage**: The traffic flowing over the N9 interface between Edge and Centralized UPFs.

## Visualization

Use the provided plotting scripts to visualize the results:

```bash
julia --project=. scripts/plot_evolution.jl
```

This will generate plots in the `images/evolution/` directory, comparing the load distribution across the different tiers.
