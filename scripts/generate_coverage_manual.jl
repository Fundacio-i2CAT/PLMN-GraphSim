using Pkg
Pkg.activate(; temp=true)
Pkg.add("Coverage")
using Coverage
println("Running tests with coverage...")
# We run in a subprocess to ensure proper coverage tracking
# --code-coverage=user: only track user code (not base/stdlib)
# --project=.: use the current project
cmd = `julia --project=. --code-coverage=user test/runtests.jl`
run(cmd)
println("Processing coverage files...")
# process_folder looks for .cov files in the source directory
coverage = process_folder("src")

# 3. Clean up (optional, but good to remove 0% coverage files from things we don't care about if any)
Coverage.clean_folder("test") # This removes the .cov files after processing

# 4. Generate LCOV file
output_file = "lcov.info"
println("Generating LCOV file: $output_file")
LCOV.writefile(output_file, coverage)

# 5. Clean up .cov files
clean_folder("src")

println("\nCoverage analysis complete.")
println("Generated $output_file")
