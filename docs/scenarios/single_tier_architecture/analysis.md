# Analysis

## Methodology
- **Simulation Duration:** 100 time steps.
- **Scenarios:**
    - **Movistar (Spain):** Smaller topology, moderate density.
    - **Verizon (USA):** Large topology, high density.


| Configuration  | Total 5G Mem (MB) | Total 6G-RUPA Mem (MB) | Reduction Factor | Max 5G Entries | Max 6G Entries |
| -------------- | ----------------- | ---------------------- | ---------------- | -------------- | -------------- |
| Movistar_Spain | 1395.31           | 0.82                   | **1698.9x**      | 16618000       | 6493           |
| Verizon_USA    | 9434.78           | 2.06                   | **4574.1x**      | 42424000       | 7265           |

The main take here is that if we compare the total memory used by the 5G architecture versus the 6G-RUPA architecture, we can see a massive reduction in memory usage, with reduction factors of **1698.9x** for Movistar Spain and **4574.1x** for Verizon USA.

Let's break down the results further.

## Distribution of Table Sizes

![Box Plot of Table Sizes](./boxplot_table_sizes.png)

### Understanding the Distribution

The box plot above illustrates the distribution of forwarding table sizes (number of entries) for every UPF (in 5G) and GUPF (in 6G-RUPA) in the simulation. 

The plot shows:

*   **Y-Axis (Log Scale):** The number of entries is plotted on a logarithmic scale to accommodate the massive difference between architectures.
*   **The Box:** Shows the middle 50% of the UPFs. The horizontal line inside is the median size.
*   **Whiskers & Outliers:** The whiskers show the range of typical values, while individual points represent outliers—UPFs with exceptionally high or low loads.

So the separation between the two groups is **essentially three orders of magnitude**. This means that even the largest GUPF in 6G-RUPA has a forwarding table size that is about 1000 times smaller than the smallest UPF in 5G.

## Evolution of Network Memory per UPF and GUPF over time

!!! note
    Memory is calculated by multiplying every entry by the scaling factor and the size of each entry.
    * The scaling factor represent the number of users each agent represents in the simulation. So if an agent represents 100 users, each entry in the UPF table represents 100 PDU sessions.

### Global Comparison
![Total Memory Comparison](./total_memory_comparison.png)
![Average Memory per UPF](./average_memory_per_upf.png)

### Movistar Spain
![Evolution Memory Movistar 5G](./evolution_5g_Fwd_State_Info_Size_MB_Movistar_Spain_Distributed.png)
![Evolution Memory Movistar 6G](./evolution_6grupa_Fwd_State_Info_Size_MB_Movistar_Spain_Distributed.png)

### Verizon USA
![Evolution Memory Verizon 5G](./evolution_5g_Fwd_State_Info_Size_MB_Verizon_USA_Distributed.png)
![Evolution Memory Verizon 6G](./evolution_6grupa_Fwd_State_Info_Size_MB_Verizon_USA_Distributed.png)

## Evolution of Number of Entries per UPF and GUPF over time

One could argue that memory can be optimized and is somehow implementation dependent, but the number of entries is a more abstract metric that indicates the actual state the UPFs need to maintain, no matter how you later implement the data structures.

### Movistar Spain
![Evolution Entries Movistar 5G](./evolution_5g_Entries_Movistar_Spain_Distributed.png)
![Evolution Entries Movistar 6G](./evolution_6grupa_Entries_Movistar_Spain_Distributed.png)

### Verizon USA
![Evolution Entries Verizon 5G](./evolution_5g_Entries_Verizon_USA_Distributed.png)
![Evolution Entries Verizon 6G](./evolution_6grupa_Entries_Verizon_USA_Distributed.png)

## Some Insights

### Hardware Acceleration Becomes Impossible

The difference between 9.4 GB (5G) and 2 MB (6G-RUPA) is of three orders of magnitude. In software (x86, COTS servers), 9 GB is somehow manageable. But in high-speed networking hardware (ASICs, P4 switches, Routers), memory is scarce and expensive. So essentially 5G UPFs cannot essentially run in hardware at scale. On the other hand, 6G-RUPA would fit entirely inside of a L2 cache of a standard CPU or hte on-chip SRAM of a commodity switch.

s6G-RUPA enables wire-speed forwarding that is physically impossible with the 5G architecture at this scale.

### Zero-Marginal Cost of Users

6G-RUPA exhibits $O(1)$ state complexity with respect to user count. That basically means that adding the 10-millionth user to the 6G network **costs zero additional forwarding memory**. 5G has $O(N)$ state complexity, which essentially means that adding them to 5G costs **the same as the first user**

### Lookup speed (which translate to latency)

Memory size correlates directly with lookup speed, which in turn has to do with latency. The router has to find one specific ID among **42 million** entries (the "biggest" UPF at Verizon) whereas in 6G-RUPA the lookup is among **7 thousand** entries for the exact GUPF.

Not only that, but 5G by definition, needs to look up for an **exact match** algorithm. On the contrary 6G-RUPA will do the lookup using **topological prefix match** which is some sort of **longest prefix match**.
