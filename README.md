# Wind–Solar–Hydrogen–Ammonia Dispatch

Fixed-capacity, grid-connected ammonia scheduling with annual carbon limits,
firm delivery contracts and hydrogen reserves. MATLAB + Optimization Toolbox.

## Start here

```matlab
cd('<PROJECT_ROOT>')
addpath('src/pipeline')
run_quick_tests();
```

For direct model/stage calls, initialize the shared source path first:

```matlab
addpath('src/utils')
setup_project_paths();
```

## Commands

| Command | Purpose |
|---|---|
| `run_quick_tests()` / `run_full_tests()` | Regression checks / complete suite. |
| `run_stage0_quality_gate()` | Tests, protocol checks and result audit reports. |
| `run_reproduce_core_results()` | Recompute annual baseline and fixed-contract case. |
| `run_reproduce_full_grid()` | Recompute reserve and joint grids; potentially expensive. |
| `run_feasibility_boundary(struct('save_output',false))` | Preview strict boundary cases without solving or replacing summaries. |
| `run_full_campaign(config)` | Calibration/lock orchestration; lock requires eligible selection. |
| `export_main_tables()` / `export_main_figures()` | Collect drafting inputs; eligibility requires separate review. |

`run_in_matlab.m` remains the F5 full-campaign shortcut and can start long solves.
Existing year-specific campaign entry points remain available.

## Evidence and documentation

The frozen v5.2 calibration selected **no eligible 2024 candidate**. Current
strict rolling boundary cases do not support a positive stability claim.
Forecasts are simulated; observed oracle is diagnostic only.

- [Workflow, layout and verification](docs/reproducibility.md)
- [Frozen scientific protocol](docs/protocol_v5.md)
- [Negative evidence and claim boundary](docs/v52_negative_evidence_freeze.md)
- [Generated reports](docs/reports/) — dated snapshots, not proof that every result is feasible.
- [Historical narrative](docs/history/manuscript_narrative.md) — superseded, not current conclusions.
