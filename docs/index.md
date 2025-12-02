# Julia-based Discrete Event Simulator for evaluating scalability of 5G Networks and beyond

This is the documentation for the Julia-based Discrete Event Simulator designed to evaluate the scalability of 5G networks and beyond.

The simulator allows researchers and network engineers to model, simulate, and analyze various network scenarios, focusing on the deployment and performance of User Plane Functions (UPFs) across different geographic regions.

## Key Components

The simulator is built around three main elements:

* :busts_in_silhouette: **Agents**: Representing users or devices distributed across municipalities within a country.
* :satellite_antenna: **Base Stations**: Using OpenCellID data to simulate real-world cellular network coverage.
* :gear: **UPFs**: UPFs get automatically distributed based on K-Means clustering, depending on agent locations. In other words, UPFs are placed in optimal locations to minimize latency and maximize performance for the distributed agents.

!!! tip "Data Sources"
    You just need to worry about providing enough data for the agents using a trustable source. For example:
    
    * In **Spain** :flag_es:, you can use the INE (Instituto Nacional de Estadística).
    * In the **USA** :flag_us:, you can use the Census Bureau.
    
    More information about how to prepare the data can be found in the [Agents documentation](agents/getting-data-ready.md).

It supports multiple countries and operators, enabling comprehensive testing of network configurations and strategies. So far it has support for Spain and the USA, but more countries can be easily added by following the [Agents documentation](agents/getting-data-ready.md).

!!! info "Current Focus: eMBB"
    Currently the simulator is focused on evaluating the performance of **enhanced Mobile Broadband (eMBB)** services. Future updates may include support for other 5G service types such as Ultra-Reliable Low Latency Communications (URLLC) and Massive Machine Type Communications (mMTC).

    That's why the simulator assumes that each user has two PDU sessions: one for Internet and another one for IMS/VoNR. You can play a bit with that in the `config.toml` file:

    ```toml
    # Number of PDU Sessions per User (e.g., Internet + IMS/VoNR)
    # This changes depending on the use case. Since we only are measuring eMBB for now, we only have two.
    min_sessions_per_user = 1
    max_sessions_per_user = 2
    ```

