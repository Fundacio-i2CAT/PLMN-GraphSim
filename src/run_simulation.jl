using Agents
using ConcurrentSim
using ResumableFunctions
using Graphs
using MetaGraphsNext
using Distributions
using Random
using Printf

# --- Shared Structures (from state_scalability.jl) ---

# 5G Structures
struct FAR
    action::UInt8
    destination_ip::UInt32
end

struct SessionContext5G
    ul_teid::UInt32
    dl_teid::UInt32
    ul_far::FAR
    dl_far::FAR
end

# 6G Structures
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

# --- Simulation State ---

mutable struct SimGlobalState
    # 5G: List of all active session contexts (Linear growth)
    active_sessions_5g::Vector{SessionContext5G}
    
    # 6G: Topological state (Constant growth)
    # We assume the routing table is static or updates rarely, 
    # but for comparison, we keep the structure.
    forwarding_table_6g::Vector{ForwardingEntry6G}
    qos_profiles_6g::Vector{QoSConfig6G}
    
    # Metrics
    history_time::Vector{Float64}
    history_size_5g_mb::Vector{Float64}
    history_size_6g_mb::Vector{Float64}
end

function create_session_context()
    return SessionContext5G(
        rand(UInt32), rand(UInt32),
        FAR(0x01, rand(UInt32)), FAR(0x01, rand(UInt32))
    )
end

function init_global_state()
    # Initialize 6G state (Constant)
    fwd = [ForwardingEntry6G(0x0A000000, 0xFFFFFF00, 1), ForwardingEntry6G(0x0A000100, 0xFFFFFF00, 2)]
    qos = [QoSConfig6G(Int8(i), Int8(i), 0.5, 1e-6) for i in 1:16]
    
    return SimGlobalState(
        Vector{SessionContext5G}(),
        fwd,
        qos,
        Float64[],
        Float64[],
        Float64[]
    )
end

# --- DES Processes ---

@resumable function user_lifecycle(env, user_id, sim_state)
    # User arrives
    arrival_delay = rand(Exponential(2.0)) # Random arrival
    @yield timeout(env, arrival_delay)
    
    # User connects and establishes 1 session
    # println(env, "User $user_id connecting at $(now(env))")
    
    # Create 5G State (Allocation)
    ctx = create_session_context()
    push!(sim_state.active_sessions_5g, ctx)
    
    # Record Metrics
    record_metrics(env, sim_state)
    
    # User stays active for some time
    duration = rand(Exponential(10.0))
    @yield timeout(env, duration)
    
    # User disconnects (State Cleanup)
    # In a real array, we'd remove specific indices, but for size tracking:
    # We just pop the last 1 for performance in this mock, 
    # representing memory being freed.
    if length(sim_state.active_sessions_5g) >= 1
        pop!(sim_state.active_sessions_5g)
    end
    
    record_metrics(env, sim_state)
end

function record_metrics(env::Environment, sim_state::SimGlobalState)
    current_time = now(env)
    
    # Measure 5G State
    size_5g = Base.summarysize(sim_state.active_sessions_5g) / (1024^2)
    
    # Measure 6G State (Includes the fixed tables)
    # Note: In 6G, user sessions don't add forwarding state to the core, 
    # they might add flow state at the edge, but the core is stateless/aggregated.
    size_6g = (Base.summarysize(sim_state.forwarding_table_6g) + 
               Base.summarysize(sim_state.qos_profiles_6g)) / (1024^2)
               
    push!(sim_state.history_time, current_time)
    push!(sim_state.history_size_5g_mb, size_5g)
    push!(sim_state.history_size_6g_mb, size_6g)
end

# --- Main Simulation Loop ---

function run_des_simulation(num_users::Int, sim_duration::Float64)
    sim = Simulation()
    global_state = init_global_state()
    
    println("Starting DES Simulation for $num_users users...")
    
    for i in 1:num_users
        @process user_lifecycle(sim, i, global_state)
    end
    
    run(sim, sim_duration)
    
    println("Simulation Complete.")
    println("Final 5G UPF State Size: $(last(global_state.history_size_5g_mb)) MB")
    println("Final 6G-RUPA GUPF State Size: $(last(global_state.history_size_6g_mb)) MB")
    
    return global_state
end

if abspath(PROGRAM_FILE) == @__FILE__
    # Run a small test
    run_des_simulation(1000, 50.0)
end
