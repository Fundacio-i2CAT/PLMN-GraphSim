using Printf

# --- 5G Structures (Linear Growth) ---
# Equation 4: S_UPF = N * 2 * (C_FAR + C_TUN)
# We use 'isbits' types (primitive types) to simulate a highly optimized 
# C/C++ data plane implementation where structures are packed in memory.
# This provides a "best case" lower bound for 5G memory usage.

struct FAR
    action::UInt8          # 1 byte (e.g., 1=FORWARD, 2=DROP)
    destination_ip::UInt32 # 4 bytes
    # In reality, FARs are larger (QoS IDs, buffering flags, etc.), 
    # but we keep it minimal to be conservative.
end

struct SessionContext5G
    ul_teid::UInt32      # 4 bytes
    dl_teid::UInt32      # 4 bytes
    ul_far::FAR          # FAR struct
    dl_far::FAR          # FAR struct
end

# --- 6G Structures (Constant Growth) ---
# Equation 7/8: S_GUPF = 2 * C_fwd + Q * C_QoS
# Topological aggregation means we route by prefix, not per tunnel.

struct ForwardingEntry6G
    dest_prefix::UInt32
    mask::UInt32
    output_interface::Int32
end

struct QoSConfig6G
    qfi::Int8
    priority::Int8
    packet_delay_budget::Float64
    packet_error_rate::Float64
end

struct GUPFState6G
    forwarding_table::Vector{ForwardingEntry6G}
    qos_profiles::Vector{QoSConfig6G}
end

function run_scalability_test()
    user_counts = [100, 1000, 10000, 100_000, 1_000_000]
    sessions_per_user = 3 # Scenario 3: Enterprise, Backup, Internet

    println("| User Count | 5G UPF State (MB) | 6G-RUPA GUPF State (MB) | Explosion Factor |")
    println("|------------|-------------------|-------------------------|------------------|")

    for N in user_counts
        # --- 5G Simulation ---
        # Total sessions = N * 3
        total_sessions = N * sessions_per_user
        
        # Create state for all sessions.
        # Since SessionContext5G is an immutable 'isbits' struct, 
        # Julia allocates this as a contiguous block of memory (like a C array).
        state_5g = Vector{SessionContext5G}(undef, total_sessions)
        
        # We don't strictly need to fill it with random data to measure size 
        # if it's a flat array of bits, but let's do it for correctness 
        # in case summarysize checks something deep (it doesn't for isbits, but good practice).
        # Filling 3 million items might be slow in a loop, so we can just measure the allocated array.
        # Base.summarysize will report the size of the array buffer.
        
        size_5g_bytes = Base.summarysize(state_5g)
        size_5g_mb = size_5g_bytes / (1024^2)

        # --- 6G Simulation ---
        # State is constant regardless of N.
        # 2 Forwarding entries (DN, gNB)
        # 16 QoS flows
        
        fwd_table = [
            ForwardingEntry6G(0x0A000000, 0xFFFFFF00, 1), # Route to DN
            ForwardingEntry6G(0x0A000100, 0xFFFFFF00, 2)  # Route to gNB
        ]
        
        qos_table = [QoSConfig6G(Int8(i), Int8(i), 0.5, 1e-6) for i in 1:16]
        
        state_6g = GUPFState6G(fwd_table, qos_table)
        
        size_6g_bytes = Base.summarysize(state_6g)
        size_6g_mb = size_6g_bytes / (1024^2)

        # Explosion Factor
        factor = size_5g_mb / size_6g_mb

        @printf("| %10d | %13.4f | %13.8f | %16.2f |\n", N, size_5g_mb, size_6g_mb, factor)
        
        # Clean up 5G state to free memory for next iteration
        state_5g = nothing
        GC.gc()
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_scalability_test()
end
