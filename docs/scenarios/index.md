# Scenarios

Explore the different simulation scenarios available in the project.

If you are looking for what the published runs actually measure — which run produced a
figure, what it holds fixed, and what it is evidence for — start with
[What Gets Evaluated](evaluation-runs.md).

<div class="grid cards" markdown>

-   :material-clipboard-check: **What Gets Evaluated**

    ---

    The six evaluation runs behind every reported number: what each varies, what it
    controls for, and the known artifacts.

    [:octicons-arrow-right-24: Read](evaluation-runs.md)

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

    [:octicons-arrow-right-24: View Setup](mobility/setup.md)
    [:octicons-graph-24: View Analysis](mobility/analysis.md)

</div>
