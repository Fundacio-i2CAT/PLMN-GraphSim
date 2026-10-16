# eMBB Focus

Currently the simulator is focused on evaluating the performance of **enhanced Mobile Broadband (eMBB)** services. Future updates may probably include support for Massive Machine Type Communications (mMTC).

That's why the simulator gives each user one or two PDU sessions, drawn uniformly: one for Internet and, for some users, a second one for IMS/VoNR. You can play a bit with that in the `config.toml` file:

```toml
# Number of PDU Sessions per User (e.g., Internet + IMS/VoNR)
# This changes depending on the use case. For eMBB each user gets one or two, drawn uniformly.
min_sessions_per_user = 1
max_sessions_per_user = 2
```
