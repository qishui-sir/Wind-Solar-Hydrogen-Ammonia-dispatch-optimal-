# v5.2 Negative Evidence Freeze

## Status

Frozen on 2026-08-28 after the 2024 simulated-persistence calibration grid
and the attempted 2025 lock run.

## Evidence Location

Archive directory:

`runs/archive/v52_negative_20260828/`

The archive stores the small decisive evidence files and SHA-256 manifests.
It does not duplicate all 156 rolling candidate MAT files. Those candidate
files are instead referenced by `rolling_2024_candidate_hashes.csv`.

## Frozen Files

- `evidence_manifest.csv`: hashes of copied evidence files.
- `rolling_2024_candidate_hashes.csv`: hashes of all 156 2024 candidate MAT
  files under `runs/stage5/joint_grid/rolling/`.
- `runs__stage2__v52_selection_audit_2024_latest.csv`: row-level v5.2
  selection audit.
- `runs__stage2__v52_selection_audit_2024_latest.mat`: MATLAB copy of the
  same audit.
- `runs__stage5__joint_grid__v51_joint_grid_2024_latest.mat`: 2024 Stage 5
  grid summary.
- `runs__rolling__v51_economic_only_2025_latest.mat`: failed 2025
  economic-only lock snapshot.
- `runs__rolling__v51_contract_plan_and_hb_smoothing_2025_latest.mat`: 2025
  rolling baseline snapshot.
- `runs__stage1__zhou_s2_baseline_2025_latest.mat`: 2025 annual baseline
  source for the failed lock attempt.
- `runs__campaign_log.txt`: campaign log showing the 2024 no-eligible result
  and the subsequent 2025 failure path.
- `docs__protocol_v5.md`: protocol snapshot used to interpret the run.

## 2024 Calibration Outcome

The 2024 simulated-persistence Stage 5 audit contains 157 rows: one reference
baseline and 156 candidate rows.

- Eligible candidates: 0.
- Completed candidate rows: 156.
- Hard-feasible candidate rows: 0.
- Candidate rows satisfying annual CO2: 0.
- Candidate rows satisfying strict delivery: 0.
- Candidate restoration day count: 249 for all 156 candidates.
- Candidate CO2 intensity range: 0.9560 to 0.9619 kg CO2/kg NH3.
- Candidate LCOA range: 545.22 to 546.65 USD/t.

Interpretation: v5.2 did not produce confirmatory evidence of a feasible
improvement under simulated persistence. Rows with restoration continuation
are retained as diagnostic evidence, not selectable manuscript evidence.

## 2025 Lock Failure

The 2025 economic-only lock run is frozen as a failure snapshot, not as a
completed result.

- File: `runs__rolling__v51_economic_only_2025_latest.mat`.
- `run_info.status`: `requires_slack_diagnosis`.
- `run_info.scheme`: `economic_only`.
- `run_info.forecast_mode`: `simulated_persistence`.
- `run_info.failed_day`: 2.
- Failure state: H2 inventory 3912.038 kg, AEL online modules 16, HB load
  0.800.

Interpretation: this file must not be used by restart logic as a completed
artifact. It is post-calibration diagnostic evidence that campaign governance
needed stricter completion validation before any future confirmatory lock.

## Manuscript Boundary

This freeze supports a negative v5.2 conclusion: no eligible 2024 candidate
was selected under the frozen v5.2 criteria. The opened 2025 run is no longer
a clean blind validation year for a later revised protocol unless that revised
protocol explicitly treats it as post-hoc stress-test evidence.

As a reviewer-facing claim boundary, this means the project is ready to draft
the protocol, Methods, reproducibility governance, and negative feasibility
evidence sections. It is not yet ready to claim that the three-variable
optimization improves ammonia production stability under realistic forecasts.
That positive claim requires strict no-restoration feasibility cases and a
forecast-quality treatment that is not limited to the weakest persistence
lower bound.
