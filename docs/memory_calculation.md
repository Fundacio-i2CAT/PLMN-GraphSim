# Memory Calculation Methodology

## Allocated Memory (Capacity)
*   **Method**: `Base.summarysize(vector)`
*   **Description**: Represents the actual RAM footprint of the data structure.
*   **Details**:
    *   Includes memory for active elements.
    *   Includes **reserved capacity**: Memory allocated by the system for future growth (dynamic array over-provisioning) that is currently empty.
    *   Includes structure overhead (pointers, length/capacity counters).
    *   **Significance**: Reflects the real-world cost of dynamic state management, where memory is allocated in chunks (e.g., doubling size) and often not immediately released when elements are removed (hysteresis).

## Used Memory (Raw)
*   **Method**: `length(vector) * sizeof(Element)`
*   **Description**: Represents the theoretical minimum memory required to store the active data.
*   **Details**:
    *   Calculated strictly as the size of the data struct (e.g., `SessionContext5G` is 24 bytes) multiplied by the number of active entries.
    *   Excludes all overhead and reserved space.
    *   **Significance**: Represents the "ideal" lean state if memory management were perfect with zero overhead.
