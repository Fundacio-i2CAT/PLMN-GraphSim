# Simulation Details

## eMBB Focus

Currently the simulator is focused on evaluating the performance of **enhanced Mobile Broadband (eMBB)** services. Future updates may probably include support for Massive Machine Type Communications (mMTC).

That's why the simulator assumes that each user has two PDU sessions: one for Internet and another one for IMS/VoNR. You can play a bit with that in the `config.toml` file:

```toml
# Number of PDU Sessions per User (e.g., Internet + IMS/VoNR)
# This changes depending on the use case. Since we only are measuring eMBB for now, we only have two.
min_sessions_per_user = 1
max_sessions_per_user = 2
```
