# Analysis

## Methodology
- **Simulation Duration:** 100 time steps.
- **Scenarios:**
    - **Movistar (Spain):** Smaller topology, moderate density.
    - **Verizon (USA):** Large topology, high density.


| Configuration  | Total 5G Mem (MB) | Total 6G-RUPA Mem (MB) | Reduction Factor | Max 5G Entries | Max 6G Entries |
| -------------- | ----------------- | ---------------------- | ---------------- | -------------- | -------------- |
| Movistar_Spain | 3346.25           | 0.87                   | **3863.3x**      | 5394000        | 5899           |
| Verizon_USA    | 21252.14          | 2.17                   | **9780.2x**      | 15726000       | 7573           |

The main take here is that if we compare the total memory used by the 5G architecture versus the 6G-RUPA architecture, we can see a massive reduction in memory usage, with reduction factors of **3863.3x** for Movistar Spain and **9780.2x** for Verizon USA.

Let's break down the results further.

## CDF of Table Sizes



## Evolution of Network Memory per UPF and GUPF over time

!!! note
    Memory is calculated by multiplying every entry by the scaling factor and the size of each entry.
    * The scaling factor represent the number of users each agent represents in the simulation. So if an agent represents 100 users, each entry in the UPF table represents 100 PDU sessions.


## Evolution of Number of Entries per UPF and GUPF over time

One could argue that memory can be optimized and is somehow implementation dependent, but the number of entries is a more abstract metric that indicates the actual state the UPFs need to maintain, no matter how you later implement the data structures.



