# Reproducibility Guide

## Scope

This guide documents how to reproduce the Stage 0 quality baseline for the wind-solar-hydrogen-ammonia dispatch project. Stage 0 is an engineering and evidence-tracing layer. It does not change the optimization model, protocol metrics, candidate grid, or scientific claims.

## Required Environment

- MATLAB with Optimization Toolbox.
- Access to the project folder and the original CSV files under `data/renewables_ninja`.
- No network access is required for Stage 0 checks.

## Project Setup

```matlab
cd('<PROJECT_ROOT>')
addpath('src/pipeline')
```

The project uses `setup_project_paths` to locate the repository root and add `src`, `src/params`, `src/results`, `src/protocol`, `src/utils`, `src/reproducibility`, `src/pipeline`, and `src/paper`.

## Stage 0 Code Layout

Stage 0 review-support code is split by responsibility:

- `src/reproducibility/stage0_manifest.m` generates file, environment, and result manifests.
- `src/reproducibility/stage0_constraint_audit.m` audits MAT result residuals.
- `src/pipeline/run_stage0_quality_gate.m` orchestrates the review-facing workflow.
- `src/utils` is limited to project root and MATLAB path setup.

## Quality Gate

Run:

```matlab
report = run_stage0_quality_gate();
```

Generated files:

- `docs/stage0_file_inventory.md`
- `docs/stage0_environment_report.md`
- `docs/stage0_constraint_audit.md`
- `docs/stage0_quality_gate_report.md`
- `runs/manifest/file_inventory.csv`
- `runs/manifest/source_manifest.csv`
- `runs/manifest/data_manifest.csv`
- `runs/manifest/environment_manifest.json`
- `runs/manifest/results_manifest.csv`
- `runs/manifest/constraint_audit.csv`
- `runs/manifest/stage0_quality_gate_report.mat`

## Tests

Fast deterministic checks:

```matlab
test_results = run_quick_tests();
```

Full test suite:

```matlab
test_results = run_full_tests();
```

Tests must not depend on manually populated base-workspace variables.

## Core Result Reproduction

Run:

```matlab
outputs = run_reproduce_core_results();
```

This recomputes the Stage 1 Zhou S2 annual baseline and the Stage 3 v5.1 fixed-contract dispatch. It then refreshes the result manifest and constraint audit.

## Full Grid Reproduction

Run only when a long solve is intended:

```matlab
outputs = run_reproduce_full_grid();
```

This recomputes Stage 4 and Stage 5 grids using the current frozen scripts. The command may be computationally expensive.

## Paper Outputs

```matlab
table_files = export_main_tables();
figure_files = export_main_figures();
```

Paper tables and figures should be generated from manifests or locked result files, not by manually copying numbers from MATLAB output.

## Result Versioning Rule

`latest.mat` files are convenience pointers. Final manuscript numbers should cite timestamped or locked files and the corresponding SHA-256 hash in `runs/manifest/results_manifest.csv`.

## Oracle Boundary

`observed_oracle` results are diagnostic upper bounds only. They must not be used as evidence for real operational forecast performance.

## Known Stage 0 Limits

Stage 0 does not validate the final scientific claim. Independent 2025 testing, uncertainty analysis, and robustness analysis belong to later phases.