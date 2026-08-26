# Wind-Solar-Hydrogen-Ammonia Dispatch Project

This repository contains MATLAB code and data for a fixed-capacity wind-solar-hydrogen-ammonia system. The reproducibility layer records source/data/result manifests, solver environment, constraint audits, and test status without changing the physical dispatch model.

## Quick Start

```matlab
cd('<PROJECT_ROOT>')
addpath('src/pipeline')
report = run_stage0_quality_gate();
```

## Main Commands

| Command | Purpose |
|---|---|
| `run_quick_tests()` | Run deterministic unit and Stage 0 tests. |
| `run_full_tests()` | Run every MATLAB test under `test/`. |
| `run_stage0_quality_gate()` | Generate manifests, environment report, result manifest, constraint audit, and test report. |
| `run_reproduce_core_results()` | Recompute Stage 1 and Stage 3 core results. |
| `run_reproduce_full_grid()` | Recompute Stage 4 and Stage 5 grids. |
| `export_main_tables()` | Export paper table inputs from manifests and comparison CSV files. |
| `export_main_figures()` | Collect existing reproducible figures for drafting. |

## Source Layout

| Folder | Responsibility |
|---|---|
| `src/params` | Physical and economic parameter definitions. |
| `src/protocol` | Frozen protocol and baseline manifests. |
| `src/results` | KPI, economics, and metric evaluation. |
| `src/reproducibility` | Stage 0 freeze checks, manifests, and constraint audits. |
| `src/stages` | Scientific experiment stage runners. |
| `src/pipeline` | User-facing run commands. |
| `src/paper` | Manuscript table and figure export adapters. |
| `src/utils` | Generic project root, path setup, and small shared helpers. |

See `docs/project_structure.md` for the full directory contract.

## Reproducibility Boundary

Stage 0 does not tune parameters, revise protocol definitions, or change model physics. It standardizes how the existing project is run, checked, documented, and traced.
