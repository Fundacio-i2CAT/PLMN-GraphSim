# Scenarios

Explore the different simulation scenarios available in the project.

<div class="grid cards" markdown>

-   :material-server: **Single-Tier Architecture**

    ---

    Baseline architecture with a flat network topology.

    ```mermaid
    graph LR
        UE([UE]) -- NR --> gNB[gNB]
        gNB -- N3 --> UPF[UPF]
    ```

    [:octicons-arrow-right-24: View Setup](single_tier_architecture/setup.md)
    [:octicons-graph-24: View Analysis](single_tier_architecture/analysis.md)

-   :material-layers: **Two-Tier Architecture**

    ---

    Hierarchical architecture with edge and regional components.

    ```mermaid
    graph LR
        UE([UE]) -- NR --> gNB([gNB])
        gNB -- N3 --> EdgeUPF(["Edge UPF"])
        EdgeUPF -- N9 --> PSA(["PSA UPF"])
    ```

    [:octicons-arrow-right-24: View Setup](two_tier_architecture/setup.md)
    [:octicons-graph-24: View Analysis](two_tier_architecture/analysis.md)

-   :material-car: **Mobility**

    ---

    Scenarios involving user movement and handovers.

    !!! warning ":construction_worker: Work in Progress :construction_worker:"
        This scenario is still under development. Stay tuned for updates!
    ```mermaid

    [:octicons-arrow-right-24: View Setup](mobility/setup.md)
    [:octicons-graph-24: View Analysis](mobility/analysis.md)

</div>
