# Ammonia Stability Protocol Archive

This archive is append-only. Later protocol versions must not replace earlier
protocol definitions or results.

## Protocol v1

- Seal: `F7987149`
- Classification: exploratory protocol-development result
- Random seed: `20260820`
- Result: no confirmatory lock
- Provisional representatives: `low_load_ratio`, `h2_soc_p05`
- Main blocker: amplitude, ramp, and switching families failed the original
  all-grid robustness gate.
- 2025 status in the final v1 run: not opened because the pre-holdout gate did
  not pass.

## Protocol v2

- Seal: `E14868F3`
- Label: `Protocol v2 / Seal E14868F3 / No-lock result`
- Formation: specified after reviewing the exploratory v1 result
- Classification: protocol-development result, not independent confirmation
- Random seed: `20260917` (different from v1)
- Result: no confirmatory lock
- Provisional representative: `low_load_ratio`
- Upper-dimension coverage: output stability only; dynamic stability and
  hydrogen security were not covered.
- Failed metric counts: mandatory deterministic 0, other deterministic 0,
  Cliff's delta 2, Spearman 12, Kendall 11, redundancy 2, incremental
  information 4, engineering 0.
- 2025 status: locked and not opened.

## Interpretation Rule

Protocol versions created after inspecting earlier results are development
protocols. A confirmatory claim requires a frozen protocol, a new random seed,
and holdout data that remain unopened until every development gate has passed.

## Protocol v3

- Seal: `70DA0F31`
- Formation: specified only after the frozen v2 diagnostic audit identified
  two conceptual rule defects.
- Classification: protocol-development lock; holdout confirmation is pending.
- Random seed: `20261023` (different from v1 and v2)
- Conceptual correction 1: threshold, quantile, window, and sampling changes
  remain diagnostic sensitivities; hard Kendall robustness uses only
  fixed-definition measurement-noise perturbations.
- Conceptual correction 2: a retained representative of a redundancy group
  cannot be eliminated solely because a redundant partner predicts the same
  target. Incremental information governs additional metrics.
- Unchanged gates: deterministic rules, Cliff's delta threshold, Spearman
  threshold, Kendall threshold, engineering rules, and three-upper-dimension
  coverage.
- Development core: `low_load_ratio`, `ramp_p95`, `switch_count`,
  `h2_min_margin`.
- Result: all three upper dimensions covered; development lock obtained.
- 2025 status: ready but manually locked; data not opened.

## Protocol v4

- Seal: `731C9F86`
- Formation: specified after reviewing the v3 development result; v1-v3 are
  retained above and were not overwritten.
- Classification: protocol-development lock; independent 2025 confirmation
  is pending.
- Random seed: `20261129` (different from v1-v3).
- Random design: one orthogonal six-factor, three-level full factorial
  (`3^6 = 729` schedules), with one common forcing profile. The sixth factor
  is low-load duration, which is required to keep `low_load_ratio` separate
  from the other five instability constructs.
- Monotonicity rule: partial Spearman on ranks against the preregistered
  target factor while controlling the other five factors. Conditional
  high-versus-low direction agreement is retained as a diagnostic.
- Definition correction: `switch_count` and `short_dwell_ratio` use the
  explicit HB binary state. Ramp metrics use online-to-online load changes.
- Robustness correction: quantile, empirical-threshold, and window grids are
  hard Kendall gates only for metrics whose definitions contain those
  parameters. Sampling remains fixed at one hour and is diagnostic only.
- Unchanged numerical gates: deterministic pass rule, Cliff's delta
  threshold, partial-Spearman threshold, Kendall threshold, redundancy,
  incremental-information, engineering, and upper-dimension coverage rules.
- Development core: `daily_shortfall_p95`, `mar`, `switch_count`,
  `h2_soc_p05`.
- Prespecified-role result: `h2_min_margin` remained a hard safety constraint
  and was not allowed to compete as a core statistical metric.
- Non-selection evidence: `rms_ramp` passed the Cliff's delta gate but failed
  the unchanged monotonicity gate (`rho = 0.65741`). `ramp_p95` failed the
  effect-size and monotonicity gates and its P90/P95/P99 Kendall robustness
  was `0.38097`, so it was not promoted from tail-risk auxiliary status.
- Result: all three upper dimensions are covered by four core metrics.
- Test result: 13 passed, 0 failed, 0 incomplete.
- 2025 status: ready but manually locked; data not opened.
