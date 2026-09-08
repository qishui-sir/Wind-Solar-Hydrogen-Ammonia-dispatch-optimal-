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

The next forecast-quality layer is `simulated_residual_scenario`: persistence
plus a 2022/2023 residual scenario library grouped by resource, month, and
hour. It is still a simulation environment, not evidence of real forecast
performance, but it closes the methodological gap between the oracle upper
bound and the persistence lower bound.

## Strict Feasibility Boundary Outcome

Stage 5 strict feasibility boundary was run with
`allow_infeasible_continuation=false` and `forecast_seed=1`. Annual full-year
oracle baselines completed for 2022-2025. Rolling observed-oracle cases were
run only for 2022/2023; 2024/2025 rolling oracle is protocol-blocked because
`observed_oracle` is restricted to development years.

All rolling strict cases failed before year end. The failure class is
`carbon_reachability_projection_binding`, meaning the day-ahead carbon
reachability projection had no feasible integer point under the current
rolling mechanism. This is stronger negative evidence than the earlier
restoration-enabled runs: without infeasible continuation, no rolling
forecast-quality layer currently supports a positive stability-improvement
claim.

| Year | Forecast layer | Failed day | Primary diagnosis |
|---:|---|---:|---|
| 2022 | observed_oracle | 354 | carbon_reachability_projection_binding |
| 2022 | simulated_persistence | 122 | carbon_reachability_projection_binding |
| 2022 | simulated_residual_scenario | 131 | carbon_reachability_projection_binding |
| 2023 | observed_oracle | 348 | carbon_reachability_projection_binding |
| 2023 | simulated_persistence | 127 | carbon_reachability_projection_binding |
| 2023 | simulated_residual_scenario | 151 | carbon_reachability_projection_binding |
| 2024 | simulated_persistence | 117 | carbon_reachability_projection_binding |
| 2024 | simulated_residual_scenario | 139 | carbon_reachability_projection_binding |
| 2025 | simulated_persistence | 145 | carbon_reachability_projection_binding |
| 2025 | simulated_residual_scenario | 157 | carbon_reachability_projection_binding |

Residual-scenario forecasts delayed failure relative to persistence in every
tested non-oracle year, but they did not restore strict feasibility. The next
optimization phase should therefore modify the rolling carbon reachability
governor or contract pacing mechanism on development/calibration evidence,
not report the current three-variable configuration as successful.

## Stage 6 Failure Diagnosis Summary

Stage 6 adds a review-facing failure evidence table without rerunning the
expensive rolling cases. The table is generated by:

```matlab
report = run_feasibility_boundary(struct( ...
    'execute', false, ...
    'save_output', true, ...
    'summarize_existing', true));
```

Output:

`runs/feasibility_boundary/failure_diagnosis_summary_latest.csv`

The summary extracts each failed rolling MAT file into one row containing the
failed day, forecast layer, primary diagnosis, carbon debt, H2 inventory,
contract backlog, carbon reserve terms, production commitment terms, and
restoration count. It is diagnostic evidence only; it does not change the
dispatch model or relax any physical, carbon, or delivery constraint.

The Stage 6 summary separates two mechanisms that were previously conflated:

- Observed-oracle failures in 2022/2023 occur with non-positive carbon debt
  at the failure state. The annual carbon budget is not exhausted, but the
  day-ahead integer dispatch cannot satisfy carbon reachability, H2 inventory,
  and contract pacing simultaneously near year end.
- Persistence and residual-scenario failures occur much earlier and mostly
  with large positive carbon debt. These are lower-quality forecast stress
  tests, not successful confirmatory runs.

Therefore, any subsequent mechanism change should be reported as a new
protocol revision or stress-test variant, not silently merged into the v5.2
negative-evidence boundary.
