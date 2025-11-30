module LoggingSetup

using Logging
using Dates

export setup_logger

function setup_logger(level::String="info")
    log_level = if lowercase(level) == "debug"
        Logging.Debug
    elseif lowercase(level) == "warn"
        Logging.Warn
    elseif lowercase(level) == "error"
        Logging.Error
    else
        Logging.Info
    end

    # Create a ConsoleLogger with the specified level
    # We can customize the format if needed, but the default is usually fine.
    # For more control, we might want to define a custom logger, but let's start simple.
    logger = ConsoleLogger(stderr, log_level)
    global_logger(logger)
    
    @info "Logger initialized with level: $log_level"
end

end
