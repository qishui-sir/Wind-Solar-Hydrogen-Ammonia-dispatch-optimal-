# ADR-001: Stage 0 Reproducibility Boundary

## Status
Accepted

## Date
2026-08-26

## Context
The project already contains a physically detailed MATLAB dispatch model, protocol documents, staged scripts, and generated MAT/CSV results. Before extending the scientific analysis, the project needs a reproducibility layer that can inventory files, record environment information, audit generated results, and run deterministic tests without changing the model.

## Decision
Add a Stage 0 quality gate around the existing model. The gate creates source/data/result manifests, records MATLAB and solver environment, audits dispatch residuals where possible, and runs quick or full MATLAB tests. It does not change dispatch physics, protocol metrics, candidate grids, or result-selection rules.

## Alternatives Considered

### Rewrite the existing stage scripts
Rejected for Stage 0 because it would mix reproducibility work with scientific logic changes and create unnecessary regression risk.

### Keep manual result tracking
Rejected because manual tracking cannot support journal-grade reproducibility or reliable manuscript number provenance.

## Consequences
- Main results can be traced to source, data, environment, and result files.
- Heavy MAT files remain ignored by default, while lightweight manifests are trackable.
- Later protocol or optimization changes can be reviewed against a stable engineering baseline.