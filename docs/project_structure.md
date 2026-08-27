# Project Structure

This project is organized so that physical modeling, experiment orchestration, reproducibility checks, generated results, and manuscript outputs remain separate.

## Top-Level Folders

| Folder | Responsibility | Manuscript role |
|---|---|---|
| `data/` | Raw renewable input data and source-side data artifacts. | Inputs that must not be overwritten by model runs. |
| `docs/` | Protocols, reproducibility notes, quality-gate reports, and ADRs. | Review-facing documentation and audit trail. |
| `runs/` | Generated MAT/CSV outputs from Stage 1-5 experiments. | Result store; heavy files are ignored except manifests. |
| `src/` | MATLAB source code. | Model, experiment, reproducibility, and export code. |
| `test/` | MATLAB unit/integration tests and small visual test artifacts. | Evidence that model interfaces and reproducibility gates work. |
| `paper_outputs/` | Exported tables and figures for drafting. | Derived manuscript artifacts, regenerated from code. |

## `src/` Boundaries

| Folder/File | Responsibility |
|---|---|
| `baseline.m`, `dispatch_model.m`, `rolling_dispatch.m`, `load_res_year.m` | Core model/data logic. |
| `stages/` | Scientific experiment stages and optimization sweeps. |
| `params/` | Physical, economic, and system parameter definitions. |
| `protocol/` | Frozen protocol and baseline manifest definitions. |
| `results/` | Cost, KPI, freeze, metric evaluation, and protocol-frozen selection routines. |
| `figures/` | Legacy or exploratory plotting code. |
| `utils/` | Generic project bootstrap and small shared helpers. |
| `reproducibility/` | Stage 0 freeze checks, manifests, and constraint audits. |
| `pipeline/` | User-facing run commands for tests, quality gate, and reproduction. |
| `paper/` | Export adapters for manuscript tables and figures. |

## Stage 0 Consolidation Rule

Stage 0 files are not generic utilities. They belong under `src/reproducibility/`.

- `stage0_freeze_check.m` verifies the frozen source/data boundary.
- `stage0_manifest.m` generates file, environment, and result manifests.
- `stage0_constraint_audit.m` audits existing MAT result residuals.
- `run_stage0_quality_gate.m` remains in `src/pipeline/` because it is an executable workflow.

This avoids scattering evidence-tracing code across `utils/` while keeping the review-facing audit layer explicit.

## Growth Control Rule

New stages should normally extend existing protocol, test, pipeline, and
manifest files. Add a new source file only when it introduces a stable
responsibility shared by multiple workflows or when an existing file has become
too large to review safely.
