# Post-Simulation Analysis Report

!!! abstract "Overview"
    This report analyzes the memory footprint differences between the legacy 5G architecture (dynamic state) and the proposed 6G-RUPA architecture (static topological state). The analysis is based on simulation results from three operators (Vodafone, Orange, Movistar) in two scenarios (Centralized, Distributed).

## Metrics Definitions

| Metric | Definition |
| :--- | :--- |
| **Allocated Memory** | Actual RAM reserved by the system (includes capacity overhead). |
| **Used Memory** | Theoretical minimum RAM needed for active data. |

## Visualizations

### :chart_with_upwards_trend: 1. Total Network Memory
*File: `total_memory_comparison.png`*

*   **What it shows**: The aggregated memory usage of the entire network.
*   **Meaning**: Demonstrates the massive efficiency gap. 5G shows a large disparity between "Allocated" and "Used" due to dynamic allocation overhead (the "bucket effect"), whereas 6G-RUPA shows near-perfect alignment, indicating high efficiency.

### :warning: 2. Bottleneck Analysis
*File: `max_memory_per_upf.png`*

*   **What it shows**: The memory usage of the single most loaded UPF in each scenario.
*   **Meaning**: Critical for hardware dimensioning. You must provision hardware for the *peak* load. This plot highlights how 5G requires significantly larger hardware resources to handle peak dynamic loads compared to the predictable, static requirements of 6G-RUPA.

### :bar_chart: 3. Typical Load
*Files: `average_memory_per_upf.png` & `median_memory_per_upf.png`*

*   **What it shows**: The central tendency of memory usage across all UPFs.
*   **Meaning**: In distributed scenarios, many UPFs might be underutilized. The median plot often reveals that while 5G has high peaks, the "typical" UPF holds significant allocated but unused memory ("zombie memory"), whereas 6G-RUPA maintains a consistent, low footprint.

### :low_brightness: 4. Baseline Load
*File: `min_memory_per_upf.png`*

*   **What it shows**: The UPF with the least load.
*   **Meaning**: Even with zero or few users, 5G UPFs retain a baseline allocated memory chunk (e.g., ~4MB) due to previous activity or initialization. 6G-RUPA's minimum is strictly determined by its topology connections, often resulting in negligible footprints for edge nodes.

!!! success "Conclusion"
    The plots collectively demonstrate that **6G-RUPA eliminates the "memory waste"** associated with dynamic state management in 5G. The static routing approach allows for precise hardware dimensioning without the need for massive over-provisioning to handle dynamic peaks and allocation overheads.
