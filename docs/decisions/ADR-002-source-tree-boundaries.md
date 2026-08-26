# ADR-002: Source Tree Boundaries

## Status
Accepted

## Date
2026-08-26

## Context
The first Stage 0 implementation placed file inventory, environment manifest, result manifest, SHA-256 hashing, and constraint audit helpers under `src/utils/`. That was functional but too broad: `utils/` mixed generic bootstrap code with review-facing reproducibility workflows.

## Decision
Keep `src/utils/` limited to generic project bootstrap helpers. Move and consolidate Stage 0 evidence-tracing code under `src/reproducibility/`:

- `stage0_manifest.m` owns file inventory, environment capture, result manifest generation, and hashing.
- `stage0_constraint_audit.m` owns residual and feasibility auditing for generated MAT results.
- `src/pipeline/run_stage0_quality_gate.m` remains the user-facing orchestration entry point.

## Alternatives Considered

### Keep five Stage 0 files in `src/utils/`
Rejected because the folder name implies generic helpers, while these files implement a specific review and reproducibility workflow.

### Put everything inside `run_stage0_quality_gate.m`
Rejected because a single large orchestration file would be harder to test and would mix workflow control with reusable manifest/audit logic.

### Keep separate files for each manifest type
Rejected for now because the three manifest generators share purpose and helpers. Consolidating them reduces navigation overhead without hiding the Stage 0 boundary.

## Consequences
- Folder responsibilities are clearer to reviewers and future maintainers.
- Stage 0 source files are fewer and named by responsibility.
- Tests and pipeline scripts call a smaller public API: `stage0_manifest` and `stage0_constraint_audit`.
- Core model files remain untouched.