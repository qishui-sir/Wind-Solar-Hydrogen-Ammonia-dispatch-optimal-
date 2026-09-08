# Workflow and Reproducibility

## Environment and startup

Use MATLAB with Optimization Toolbox and the original `data/renewables_ninja`
CSV inputs. Parallel Computing Toolbox is optional for parallel campaigns.
No network is needed for local checks.

```matlab
cd('<PROJECT_ROOT>')
addpath('src/utils')
setup_project_paths();
```

`setup_project_paths` owns the source-directory list; `project_root` finds the
root from an anchor independently of `pwd`. Public pipeline/paper commands
retain a minimal bootstrap to make `src/utils` discoverable. Avoid `genpath`
so exploratory or archived code is not automatically added.

## Directory responsibilities

| Location | Responsibility |
|---|---|
| `src/dispatch_model.m`, `baseline.m`, `rolling_dispatch.m` | Shared physics, annual solve and rolling execution. |
| `src/params`, `src/load_res_year.m` | Physical/economic parameters and renewable inputs. |
| `src/stages` | Scientific experiments and parameter sweeps. |
| `src/pipeline` | Workflows and forecast-library preparation. |
| `src/results` | Economics, metrics, selection, freezing and failure classification. |
| `src/protocol` | Frozen protocols and baseline manifest. |
| `src/reproducibility` | Manifests, hashes and constraint audits. |
| `src/utils` | Shared root/path, option lookup and directory creation. |
| `src/paper`, `src/figures` | Draft exports and exploratory plotting. |
| `test` | Existing unit/integration tests and historical indicator tests. |
| `data` | Original inputs; do not overwrite during runs. |
| `runs` | Scientific MAT/CSV results and frozen evidence. |
| `docs/reports` | Generated human-readable audit snapshots. |
| `docs/history`, `docs/decisions` | Superseded narrative and engineering decisions. |
| `paper_outputs` | Derived drafting artifacts. |

Share helpers only when semantics agree: `option_value` defaults missing/empty
values while preserving zero and false. Field lookup that preserves an explicit
empty value remains distinct. `ensure_directory` preserves existing contents.
Keep scientific responsibilities separate rather than combining everything into
one workflow file.

## Verification and reports

```matlab
run_quick_tests();
run_full_tests();
report = run_stage0_quality_gate();
```

The quality gate generates four `stage0_*.md` reports under `docs/reports`.
Machine-readable file/source/data/result manifests, environment information,
constraint audits and the gate MAT remain under `runs/manifest`.
Manifest and constraint-audit functions retain their `docs_dir` override.
Moved reports retain their original timestamps and hashes; rerun the gate when
a current snapshot is needed.

A successful engineering gate does not certify every stored scientific result.
Failed feasibility rows remain in the audit. Tests must not rely on variables
manually placed in the MATLAB base workspace.

## Scientific runs

```matlab
run_reproduce_core_results();  % Stage 1 annual + Stage 3 fixed contract
run_reproduce_full_grid();     % Stage 4/5; potentially long computation
```

Select from an existing 2024 grid without rerunning it:

```matlab
run_reproduce_full_grid(struct('run_stage4',false, ...
    'run_stage5',false,'run_v52_selection',true));
```

This writes selection audits under `runs/stage2`. Failed/ineligible candidates
remain visible; the frozen selector excludes oracle cases and requires 2024.
The negative freeze is authoritative when older narrative differs.

## Strict boundary diagnostics

```matlab
run_feasibility_boundary(struct('save_output',false)); % read-only plan
run_feasibility_boundary(struct('execute',true));      % expensive solves
run_feasibility_boundary(struct('execute',false, ...
    'summarize_existing',true));                      % rewrite diagnostic tables
```

The default `execute=false` does not solve, but `save_output=true` writes a plan;
use `save_output=false` to avoid replacing an existing summary. Boundary runs
disable restoration continuation. Rolling oracle is limited to 2022/2023.
The annual boundary entry uses Stage 1 and does not itself certify the fixed
contract; use the fixed-contract experiment for that comparison.

Persistence and residual-scenario inputs are simulations. The residual library
uses 2022/2023 data grouped by resource, month and hour; `forecast_seed` controls
sampling. A scenario label establishes neither forecast accuracy nor a
probability guarantee. Failure classification is rule-based diagnostic evidence,
not an IIS or a causal proof.

## Evidence and exports

Paper export functions collect drafting inputs into `paper_outputs`; they do not
automatically establish claim eligibility. `test/png` currently supplies legacy
figure exports and is not disposable cache.

Preserve raw data, candidate MAT files, strict failure snapshots and
`runs/archive/v52_negative_20260828`. Candidate hashes do not replace the original
MAT files. Many results are ignored by Git, so Git alone is not a backup.
Cite frozen artifacts and hashes instead of mutable `latest` files.

Scientific definitions remain in [protocol_v5.md](protocol_v5.md); claim limits
remain in [v52_negative_evidence_freeze.md](v52_negative_evidence_freeze.md).
