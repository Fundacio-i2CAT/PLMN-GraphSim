# Julia-based Discrete Event Simulator for evaluating scalability of 5G Networks and beyond

This is the documentation for the Julia-based Discrete Event Simulator designed to evaluate the scalability of 5G networks and beyond.

The simulator allows researchers and network engineers to model, simulate, and analyze various network scenarios, focusing on the deployment and performance of User Plane Functions (UPFs) across different geographic regions.

## In a Nutshell

The simulator is built around three main elements:

* **Agents**: Representing users or devices distributed across municipalities within a country.
* **Base Stations**: Using OpenCellID data to simulate real-world cellular network coverage.
* **UPFs**: UPFs get automatically distributed based on K-Means clustering, depending on **gNB density**. In other words, UPFs are placed in optimal locations to minimize latency and maximize performance for the distributed base stations.

Then, these elements are connected based on proximity.

```mermaid
graph LR
    UE([UE]) -- closest --> gNB[gNB]
    gNB -- closest --> UPF[UPF]
```


!!! tip "Data Sources"
    You just need to worry about providing enough data for the agents using a trustable source. For example:
    
    * In **Spain** :flag_es:, you can use the INE (Instituto Nacional de Estadística).
    * In the **USA** :flag_us:, you can use the Census Bureau.
    
    More information about how to prepare the data can be found in the [Agents documentation](agents/getting-data-ready.md).

It supports multiple **countries** and **operators**, enabling comprehensive testing of network configurations and strategies. So far it has support for Spain and the USA, but more countries can be easily added by following the [Agents documentation](agents/getting-data-ready.md).


## Visualizations

Explore the generated network topologies and agent distributions for our supported scenarios.

=== "Spain (Movistar) :flag_es:"

    **Topology Map**
    
    ![Topology Map Spain](images/single_tier_scenario/topology_map_cities_movistar_spain%20distributed.png)

    **Network Graph**
    
    ![Network Graph Spain](images/single_tier_scenario/graph_viz_movistar_spain%20distributed.png)
=== "USA (Verizon) :flag_us:"

    **Topology Map**
    
    ![Topology Map USA](images/single_tier_scenario/topology_map_cities_verizon_usa%20distributed.png)

    **Network Graph**
    
    ![Network Graph USA](images/single_tier_scenario/graph_viz_verizon_usa%20distributed.png)
