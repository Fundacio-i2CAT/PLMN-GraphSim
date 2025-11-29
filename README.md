# DesJulia6gRupa

## Run Simulator

Run the main simulation entry point:
```bash
julia --project=. main.jl
```

## Run Tests
Execute the test suite:
```bash
julia --project=. test/runtests.jl
```

## Test Coverage
1. Generate coverage data:
   ```bash
   julia scripts/generate_coverage_manual.jl
   ```
2. View results in VS Code:
   - Install "Coverage Gutters" extension
   - Run command "Coverage Gutters: Watch"
