# Analysis

## Methodology

!!! info "Simulation Setup"
    - **Simulation Duration:** 100 time steps.
    - **Scenarios:**
        - **Movistar (Spain):** Two-Tier architecture (Edge + Centralized).
        - **Verizon (USA):** Two-Tier architecture (Edge + Centralized).


!!! note
    The following table summarizes the statistics for the **Centralized UPFs (Tier 2)** only, as they represent the bottleneck in the core network.

| Configuration          | Total 5G Mem (MB) | Total 6G-RUPA Mem (MB) | Reduction Factor | Max 5G Entries | Max 6G Entries |
| ---------------------- | ----------------- | ---------------------- | ---------------- | -------------- | -------------- |
| Movistar_Spain_TwoTier | 1392.79           | ~0.00                  | **781,824.4x**   | 46,526,000     | 19             |
| Verizon_USA_TwoTier    | 9431.10           | ~0.00                  | **3,717,753.4x** | 196,364,000    | 24             |

The reduction factors are even more extreme here than in the single-tier scenario because the Centralized UPFs in 5G must maintain state for *all* sessions in their region, whereas in 6G-RUPA, the core routers only need to know the topology of the core network, which is very small (19-24 nodes).

## Global Statistics

![Global Statistics Dashboard](../../images/two_tier_scenario/dashboard_global_stats.png)

### Understanding the Distribution

The box plot (bottom-left in the dashboard) illustrates the distribution of forwarding table sizes (number of entries) for every UPF (in 5G) and GUPF (in 6G-RUPA) in the simulation. 

The plot shows:

*   **Y-Axis (Log Scale):** The number of entries is plotted on a logarithmic scale to accommodate the massive difference between architectures.
*   **The Box:** Shows the middle 50% of the UPFs. The horizontal line inside is the median size.
*   **Whiskers & Outliers:** The whiskers show the range of typical values, while individual points represent outliers—UPFs with exceptionally high or low loads.

## Detailed Evolution Analysis

??? note "A note on how memory is calculated"
    Memory is calculated based on the number of entries and the size of the data structures.

    *   **Entry Size:** We use a consistent **12 bytes per entry** for both architectures to ensure a fair comparison.
        *   **5G:** Derived from a 24-byte `ForwardingState5G` struct containing both Uplink and Downlink tunnels information (2 entries).
        *   **6G-RUPA:** Derived from a 12-byte `ForwardingEntry6GRUPA` struct.
    *   **Scaling:**
        *   **5G:** The number of entries is scaled by the `scale_factor` (1000 users per agent), as 5G maintains per-session state ($O(n)$).
        *   **6G-RUPA:** The number of entries is determined by the network topology and does not scale with the number of users ($O(1)$ complexity).

### Movistar Spain
![Movistar Spain Dashboard](../../images/two_tier_scenario/dashboard_evolution_Movistar_Spain_TwoTier.png)

### Verizon USA
![Verizon USA Dashboard](../../images/two_tier_scenario/dashboard_evolution_Verizon_USA_TwoTier.png)

## Key Insights

### No Bottleneck at the Centralized UPFs

In the Two-Tier architecture, the Centralized UPFs (Tier 2) act as massive aggregation points. In the 5G architecture, this creates a critical bottleneck because these nodes must maintain per-session state for millions of users across a vast region.

* **5G:** A single Centralized UPF in the Verizon scenario reaches **196 million entries**, requiring nearly **10 GB of high-speed memory**. This is physically impossible to implement in current high-speed switching hardware (ASICs), forcing these functions into slower software-based implementations.

* **6G-RUPA:** The corresponding GUPF in 6G-RUPA requires only **24 entries**. This is because it only needs to know the topology of the network (the Tier 1 routers) to route traffic.

### Complete Decoupling of State and Scale

The results demonstrate a complete decoupling of network scale (growth of number of UEs) from network state (forwarding state memory usage) in the core.

*   **Unlimited Scalability:** You could add 100 million more users to the Verizon network, and the state in the 6G-RUPA Core GUPFs would remain exactly **24 entries**.

*   **Zero-Cost Core Expansion:** Expanding the capacity of the network by adding more users has literally **zero marginal cost** in terms of memory footprint for the core routers.

### Feasibility of All-Hardware Core

The difference between **196,000,000 entries** and **24 entries** is a reduction factor of over **3.7 million**. That means that in 6G-RUPA you can fit the entire forwarding table for a core router into a few **bytes** of register memory. This allows the core network to be built using ultra-fast, simple, and energy-efficient programmable switches (like P4 switches) without external memory, operating at terabits per second with deterministic latency.