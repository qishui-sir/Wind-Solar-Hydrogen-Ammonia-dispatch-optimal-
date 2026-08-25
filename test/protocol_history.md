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

## Protocol v5

- Seal: `6B71CCF0`
- S2 baseline manifest seal: `9FE68D80`
- Freeze date: `2026-08-21`
- Formation: specified after reviewing the v4 development selection and the
  2022 real S2 dispatch. Earlier versions and their results remain above.
- Classification: result-informed prospective boundary protocol, not a fully
  outcome-blind preregistration and not yet a complete confirmatory analysis
  plan.
- Prospective scope: the new forecast model, forecast-error-driven hydrogen
  reserve trajectory, contract-backlog ammonia plan, coordinated scheduling
  results, and any v5 evaluation on 2025 were not inspected at freeze time.
- Metric provenance: `mar`, `h2_soc_p05`, and legacy
  `daily_shortfall_p95` are explicitly labeled as v4 data-selected metrics.
  `contract_shortfall_p95` and reserve frequency, duration, and depth outcomes
  are mechanism-defined after diagnosing the baseline limitations.
- S2 exclusion: `switch_count` is not applicable because the positive S2 HB
  lower bound makes the unit always online.
- Baseline caveats: renewable scale `0.8623`, 30 MW grid contract, 200 FTE,
  absolute pressure basis, and S3 startup electricity in S2 are separately
  identified as calibration assumptions or study overrides rather than all
  being attributed to Zhou.
- Known 2022 results: archived as descriptive evidence only and prohibited
  from becoming v5 acceptance thresholds.
- 2025 status: analysis locked but not strictly blind. The file existed and
  limited raw content was exposed during repository auditing; no v5 model
  outcome was used for selection or tuning. A new unseen year or independent
  station is required for strong external confirmation.
- Change control: required forecast, risk, statistical, and failure-handling
  details must be added as an append-only v5.1 subprotocol before any new
  model or 2025 outcome is opened.

## Protocol v5.1.1 contract amendment

- Seal: `4C220818`; supersedes the unused v5.1.0 contract seal `DDD87B18`.
- Timing: amended before the first contract-aware optimization result.
- Firm contract: endogenous constant daily quantity on existing Zhou S2 assets.
- Delivery rule: seven-day maximum backlog, no early-delivery credit, and zero
  terminal backlog.
- Equipment scope: no ammonia storage and no new hydrogen-storage capacity.
- Economics: maximize firm quantity under a 2% stage1 LCOA cap, then minimize
  the original annual cost-minus-revenue objective at that quantity.

## Protocol v5.1.2 solver amendment

- Seal: `73084D40`; supersedes v5.1.1 seal `4C220818`.
- Trigger: the first annual capacity run reached 600 seconds at the root node
  without an integer feasible point. It produced no feasible dispatch result.
- Warm start: the stage1 integer dispatch plus its maximum supported no-credit
  contract quantity and backlog trajectory.
- Capacity phase gap: 0.5%; economic phase gap: 0.01%.
- The seven-day contract, terminal-zero rule, equipment scope, 2% LCOA cap,
  and lexicographic objective order are unchanged.

## Protocol v5.1.3 fixed-candidate search amendment

- Seal: `98AB91E8`; supersedes v5.1.2 seal `73084D40`.
- Trigger: with the stage1 incumbent loaded, the direct capacity objective
  remained at the root node with a 20.12% gap after 1048.5 seconds; its LP
  bound improved by only about 0.113 t/a after 28.4 seconds.
- Equivalent search: fix one annual contract candidate per MILP, retain all
  hard contract and physical constraints, and restore the economic objective.
- Initial candidates: 70000, 73000, and 76022.964275 t-NH3/a; refine the
  feasible/infeasible bracket to 0.5% only after the coarse screen.
- A timeout with an integer incumbent proves candidate feasibility only. A
  timeout without an incumbent is unresolved, not infeasible.
- Solver-reported infeasibility requires the frozen slack diagnosis before any
  constraint or route change.

## Protocol v5.1.4 common-contract freeze

- Seal: `BCEFDEC8`; supersedes v5.1.3 seal `98AB91E8`.
- Trigger: the stage1 MAT actual output candidate, 76022.964275 t-NH3/a,
  returned a feasible economic optimum under the unchanged seven-day,
  no-early-credit, terminal-zero, existing-assets, and 2% LCOA-cap rules.
- Frozen contract: 76022.964275 t-NH3/a, or 208282.093904 kg-NH3/day, as the
  common exogenous contract for every following scheme.
- Source precision: the stage1 MAT value is 76022.9642746094 t-NH3/a; the
  contract is its value rounded to six decimal places.
- Evidence: `runs/stage3/v51_contract_candidate_076022p964t_2022_latest.mat`,
  generated under v5.1.3 / `98AB91E8`; actual output 78194.835018 t-NH3/a,
  LCOA 469.052359 USD/t, LCOA increase 0.832385%, and net profit 6.877051 MUSD.
- Contract checks: maximum backlog equals the seven-day limit, terminal backlog
  is numerical zero, and the economic solver gap is `9.983963e-5`.
- Interpretation: this proves feasibility at the frozen contract but does not
  prove maximum contract capacity or unused delay margin.
- Capacity maximization and candidate bracketing are stopped and retained only
  as diagnostic history. They no longer select the contract.
- Rationale: freezing the stage1 MAT output preserves a common comparison basis
  and avoids selecting the contract from the same 2022 perfect-information
  dispatch used to evaluate it.

## Protocol v5.1.5 rolling-dispatch amendment

- Seal: `69F535A8`; supersedes v5.1.4 seal `BCEFDEC8` without changing the
  frozen annual contract.
- Timing: frozen before any rolling-dispatch or realtime-recourse result.
- Delivery semantics: each daily contract cohort must be served from its due
  day through due day plus seven; no production before the due day is credited.
- Existing certificate check: the v5.1.3 frozen dispatch has maximum FIFO
  completion delay seven days, zero late cohorts, and zero unserved cohorts.
- Forecast horizon: one forecast issue per operating day covering hours 1-72.
- Rolling horizon: plan 72 hours, commit 24 hours, and replan every 24 hours.
- Realtime recourse: fix HB load and AEL integer commitment; only AEL continuous
  power, grid purchase, grid sale, and curtailment may adjust.
- Hydrogen terminal rule: planned terminal inventory cannot be below either the
  window-opening inventory or the terminal reserve target; annual terminal
  inventory equals annual initial inventory.
- Emergency slack is diagnostic only. A dispatch requiring slack is rejected.
- Approved source modules: `src/dispatch_model.m` and
  `src/rolling_dispatch.m`; neither is connected to `main.m` before closure.

## Protocol v5.1.6 annual-carbon-accounting correction

- Seal: `E623EC50`; supersedes v5.1.5 seal `69F535A8` without changing the
  frozen contract, FIFO delivery, 72/24-hour timing, or fixed recourse plan.
- Trigger: the first 2022 economic rolling run passed day 1 but the day-2
  realtime replay was infeasible. Removing only the CO2 constraint restored
  feasibility; storage, transformer, sale, curtailment, and AEL commitment
  diagnostics did not explain the failure.
- Quantification: the fixed day-2 plan required at least 390.979366 MWh of
  grid purchase and 0.882171635 kgCO2/kgNH3, above the 0.3 daily value. This
  is valid evidence against applying the annual Zhou S2 limit independently
  to every 24-hour window, not evidence of annual carbon infeasibility.
- Correction: rolling state now carries cumulative grid emissions and
  cumulative NH3. Intermediate windows enforce a necessary future-recovery
  bound using physical maximum remaining HB output; year end enforces the
  original annual cumulative intensity inequality exactly.
- No independent daily carbon cap and no carbon slack are permitted. An
  annual terminal breach remains a hard infeasibility.

## Protocol v5.1.7 annual-grid-fraction correction

- Seal: `95B77A28`; supersedes v5.1.6 seal `E623EC50`.
- The 20% electricity-sale and 10% curtailment limits are independent annual
  energy fractions, not separate limits for every realtime day.
- Rolling state carries cumulative sale, curtailment, and renewable energy.
  Intermediate windows use physical remaining renewable capacity for the
  reachability bound; year end enforces both original annual limits exactly.
- Day 10 required 1095.560804 MWh beyond the two daily quotas while the first
  nine days had sufficient accumulated annual allowance. No quota exchange or
  emergency slack is allowed.

## Protocol v5.1.8 contract-anchored carbon envelope

- Seal: `0E9E2808`; supersedes v5.1.7 seal `95B77A28` without changing the
  frozen contract, existing equipment, annual carbon limit, or grid budgets.
- The physical-maximum NH3 recovery bound left only 89835.836352 kgCO2 of
  margin after day 156 while cumulative carbon debt was 17088246.355429 kgCO2;
  fixed day-ahead commitments then made day 157 realtime recourse infeasible.
- Intermediate carbon debt is now bounded by the 0.3 intensity limit times the
  remaining frozen contract NH3. This declining terminal envelope does not
  credit forecast overproduction or early contract delivery.
- At year end the remaining reference is zero, so the original annual Zhou S2
  carbon-intensity inequality remains the exact hard constraint. Carbon slack
  remains prohibited.

## Protocol v5.1.9 daily reachability checkpoints

- Seal: `F5F9D988`; supersedes v5.1.8 seal `0E9E2808` without changing annual
  limits, equipment, contract quantity, or realtime recourse controls.
- A 72-hour day-ahead plan previously checked annual reachability only at hour
  72, while its fixed commitment was replayed against the hour-24 envelope.
  This temporal mismatch produced a feasible day-130 plan and infeasible
  day-130 realtime replay.
- Day-ahead carbon, sale, and curtailment reachability are now checked at each
  24-hour boundary. These are checkpoints on declining annual state budgets,
  not independent daily quotas.

## Protocol v5.1.10 adaptive forecast-error carbon reserve

- Seal: `4E7E3AB8`; supersedes v5.1.9 seal `F5F9D988` without changing the
  annual carbon definition, contract, equipment, or realtime hard constraints.
- Day 130 overpredicted renewable energy by 1963.629560 MWh. Its fixed plan
  required at least 649.980251 MWh of actual grid purchase and exceeded the
  carbon envelope by the equivalent of 509.071249 MWh.
- The first committed day now carries a one-sided expanding-window empirical
  reserve from completed persistence-forecast errors. The default quantile is
  0.95 and the finite-sample rank is `ceil((n+1)q)`, capped at `n`.
- Reserve estimation uses no future observations. Realtime and year-end models
  retain the original hard annual carbon constraint without virtual emissions.

## Protocol v5.1.11 recourse-purchase carbon reserve

- Seal: `E74AF66F`; supersedes v5.1.10 seal `4E7E3AB8` without changing the
  reserve quantile, annual limits, fixed commitments, or equipment.
- The v5.1.10 95% renewable-shortfall reserve reached 1842.045260 MWh on day
  122 and made the day-ahead model infeasible because it also reserved errors
  absorbed by adjustable AEL power, sale, and curtailment.
- With committed HB load fixed, day-ahead and realtime NH3 output are equal.
  Carbon recourse error therefore equals the positive realtime-minus-planned
  grid-purchase increment times the frozen grid emission factor.
- The expanding empirical reserve now uses that directly observed recourse
  exposure. Renewable shortfall remains a diagnostic series only.

## Protocol v5.1.12 lexicographic downward HB recourse

- Seal: `B6728D30`; supersedes v5.1.11 seal `E74AF66F` without changing hard
  carbon, storage, grid, equipment, or contract constraints.
- A 95% purchase-exposure reserve was infeasible on day 123 above a feasible
  reserve of 1100 MWh; 90% was also day-ahead infeasible on day 128. Hard
  empirical reserve is therefore retained for sensitivity analysis with a
  default quantile of zero.
- Realtime first attempts exact HB and AEL commitment replay. Only after exact
  replay is infeasible may HB move downward while AEL commitment stays fixed.
- The fallback is lexicographic: minimize NH3 deviation first, then minimize
  economic cost at that minimum deviation. It introduces no constraint slack,
  and every target and realized deviation is persisted.

## Protocol v5.1.13 carbon-state-consistent recourse

- Seal: `15911CA0`; supersedes v5.1.12 seal `B6728D30` without changing the
  hierarchical HB fallback or any annual hard limit.
- Minimal day-130 HB deviation exhausted the carbon envelope to a margin of
  0.067950 kgCO2 and made the day-131 72-hour plan carbon-infeasible.
- Realtime now preserves the day-ahead hour-24 carbon-debt checkpoint. This
  retains the endogenous look-ahead margin already required by the feasible
  72-hour plan and introduces no exogenous safety factor.

## Protocol v5.1.14 one-step carbon viability buffer

- Seal: `E65D8530`; supersedes v5.1.13 seal `15911CA0` without changing the
  annual carbon envelope or lexicographic HB fallback.
- Full checkpoint-state preservation requested 22825618.664875 kgCO2 of
  reserve on day 2 and was physically infeasible even with downward HB.
- Realtime now preserves the smaller of the planned checkpoint margin and one
  replan interval of contract-envelope erosion, `I_max * Q_daily`.
- This is a one-step MPC recursive-feasibility buffer, capped at about
  62484.63 kgCO2; it does not reserve remote annual surplus at every day.

## Protocol v5.1.15 feasible carbon-buffer projection

- Seal: `A66669E8`; supersedes v5.1.14 seal `E65D8530` without relaxing the
  original annual carbon envelope.
- The requested 62484.628171 kgCO2 day-130 buffer was physically unreachable
  even with downward HB, although the unbuffered hard envelope was feasible.
- Fallback first minimizes carbon debt under the original hard constraint to
  obtain maximum feasible margin, then projects the requested buffer onto that
  bound, minimizes NH3 deviation, and finally minimizes economic cost.
- Requested buffer and realized carbon margin are persisted separately.

## Protocol v5.1.16 downward AEL commitment recourse

- Seal: `1FC85578`; supersedes v5.1.15 seal `A66669E8` without adding equipment
  or relaxing carbon, storage, and grid constraints.
- The v5.1.15 fallback was used on days 130 and 131 with 76.422874 t of total
  NH3 deviation, yet day 132 remained carbon-infeasible because 26 committed
  AEL modules retained their minimum electrical load.
- Exact replay still fixes HB and AEL. Only after infeasibility may both targets
  move downward; all integer transitions, startup energy, minimum load, and H2
  physics remain active.
- Target and realized AEL module-hours are persisted with the HB deviations.

## Protocol v5.1.17 scheme-consistent carbon reachability

- Seal: `5660E990`; supersedes v5.1.16 seal `1FC85578` without changing the
  year-end carbon-intensity constraint.
- `economic_only` has no contract obligations, so restricting its future NH3
  reference to remaining frozen contract quantity was a model-scope mismatch.
- The no-contract comparator now uses physical maximum remaining HB output as
  a necessary intermediate reachability bound. Contract-aware schemes retain
  the remaining frozen contract reference.
- Both references reach zero at year end, where actual annual NH3 production
  remains the exact denominator of the hard Zhou S2 carbon constraint.

## Protocol v5.1.18 day-ahead reserve feasibility projection

- Seal: `DB689A40`; supersedes v5.1.17 seal `5660E990` without relaxing the
  annual carbon reachability envelope.
- The economic-only 95% reserve requested 645473.012542 kgCO2 on day 155 and
  exceeded the day-ahead feasible set.
- If the full reserve is infeasible, a first solve minimizes hour-24 carbon
  debt without extra reserve, then clips the request to that maximum feasible
  margin and re-solves the economic dispatch.
- Economic-only defaults to q=0.95; contract-aware schemes default to q=0.
  Requested and applied reserves are persisted separately.

## Protocol v5.1.19 realtime inheritance of applied reserve

- Seal: `1EAB321F`; supersedes v5.1.18 seal `DB689A40` without changing the
  reserve estimator or annual hard constraint.
- Day 155 applied 631514.273365 kgCO2 of feasible day-ahead reserve, but
  realtime retained only the one-day cap of 82191.847772 kgCO2 and left day
  156 day-ahead infeasible.
- Realtime now inherits the applied day-ahead reserve. If actual conditions
  cannot attain it, the existing three-level physical feasibility projection
  computes the maximum realizable margin before minimizing NH3 deviation.

## Protocol v5.1.20 robust physical-recovery factor

- Seal: `8012E1B8`; supersedes v5.1.19 seal `1EAB321F` without changing actual
  equipment capacity or the year-end carbon equation.
- Repeated forecast errors reduced realized margin to 99387.417589 kgCO2 on
  day 165 and made the unbuffered day-166 projection infeasible, showing that
  full physical remaining HB output was an optimistic recovery assumption.
- Economic-only credits 90% of physical maximum remaining HB output by
  default, with 0.85/0.90/0.95/1.00 as the development sensitivity grid.
- Contract-aware schemes keep the frozen contract reference with factor one.

## Protocol v5.1.21 absolute annual emissions budget

- Seal: `CE612940`; supersedes v5.1.20 seal `8012E1B8` without changing the
  exact year-end Zhou S2 intensity equation.
- Physical-recovery envelopes encouraged early grid emissions and only forced
  correction near their theoretical future-production boundary.
- Economic-only intermediate windows now enforce cumulative grid emissions
  below `0.3 * 76022.964275e3 kgNH3`. This budget is bankable across days and
  is not an independent daily intensity limit.
- The final planning window and day-365 replay enforce emissions against actual
  cumulative NH3. Contract-aware schemes retain contract-anchored carbon debt.

## Protocol v5.1.22 hydrogen-neutral must-run reserve

- Seal: `3B8C6B80`; supersedes v5.1.21 seal `CE612940` without increasing any
  equipment capacity or relaxing the annual emissions budget.
- Day 182 had 253954.101197 kgCO2 of budget left but was infeasible even after
  statistical reserve removal because HB minimum load requires continuous H2.
- A zero-renewable hydrogen-neutral minimum day needs 901.097354 MWh, equal to
  513895.820729 kgCO2 at the frozen grid factor.
- Economic-only retains the maximum of empirical and physical reserve through
  day 364, then releases it on day 365 for exact annual closure.

## Protocol v5.1.23 bankable budget with bounded borrowing

- Seal: `19E80418`; supersedes v5.1.22 seal `3B8C6B80` without changing
  equipment, the frozen annual reference, or the exact year-end intensity rule.
- Day 182 showed that exposing the full annual budget from day 1 permits early
  economic dispatch to consume emissions needed for later hydrogen-neutral
  minimum operation; a fixed one-day reserve was then projected away as the
  feasible margin contracted.
- Economic-only now accrues its absolute planning budget linearly over 8760
  hours, banks every unused kilogram of CO2, and may borrow no more than seven
  days of future accrual. This is a cumulative budget, not a daily cap.
- The final window still enforces emissions against actual annual NH3. Default
  statistical reserve is zero for both schemes; the empirical estimator remains
  available only for predefined sensitivity analysis. Economic-only retains
  the one-day hydrogen-neutral physical floor inside the scheduled budget, while
  the superseded physical-recovery-factor code path is removed.

## Protocol v5.1.24 diagnostic carbon-borrowing horizon

- Seal: `9DF524A0`; supersedes v5.1.23 seal `19E80418` without changing the
  seven-day contract-delivery limit or annual carbon equation.
- At day 183, a 72-hour minimum-emissions solve required 4.3757, 7.1501, and
  9.3578 days of borrowed accrual at its three daily checkpoints. Preserving
  the first-day hydrogen-neutral reserve raised the binding lower bound to
  12.6001 days.
- The economic-only planning budget therefore uses the next predefined discrete
  level, 14 days. Borrowed emissions remain inside the fixed annual budget and
  must be repaid before exact actual-NH3 year-end closure.

## Protocol v5.1.25 planning-horizon physical reserve

- Seal: `E1A5381F`; supersedes v5.1.24 seal `9DF524A0` without changing equipment,
  annual emissions, or the seven-day contract-delivery limit.
- A larger borrowing horizon was consumed immediately by the economic objective
  and therefore did not improve day-183 feasibility. The remaining mismatch was
  between a 24-hour physical reserve and a 72-hour planning horizon.
- Economic-only now reserves the zero-renewable hydrogen-neutral minimum energy
  for the full planning horizon: 2703.292061 MWh or 1541687.462187 kgCO2. The
  reserve is projected to the feasible set after actual errors and is not slack.

## Protocol v5.1.26 restart-viable hydrogen handoff

- Seal: `AAE62398`; supersedes v5.1.25 seal `E1A5381F` without changing storage
  capacity, annual limits, or equipment commitment physics.
- Day 323 ended at the physical H2 minimum with every AEL module offline while
  HB remained online. Day 324 was infeasible even without carbon constraints,
  identifying a state-handoff rather than an emissions-budget failure.
- Every nonfinal realtime handoff now retains one time step of minimum-HB H2,
  616.438356 kg above the 3295.600000 kg physical floor. Day-ahead handoffs also
  remain no lower than their opening inventory.

## Protocol v5.1.27 observed-renewable grid budgets

- Seal: `8C4963B7`; supersedes v5.1.26 seal `AAE62398` without changing the final
  20% electricity-sale and 10% curtailment limits.
- Day 327 had sold 229880.181 MWh, 59474.041 MWh above 20% of observed renewable
  generation. Crediting future nameplate-maximum generation postponed the
  physically unavoidable failure until day 328.
- Rolling sell and curtail budgets now use cumulative observed renewable energy
  plus only the current forecast window. Unused allowances bank across days;
  there is no independent daily cap and no future-actual-data leakage.

## Protocol v5.1.28 measured rolling-solver limit

- Seal: `C3EC6E70`; supersedes v5.1.27 seal `8C4963B7` without changing model
  constraints, objective, relative gap, or feasibility tolerance.
- The day-37 projected economic window reached the frozen 1e-4 relative gap in
  121.081 seconds with 2.79e-9 constraint violation. The previous 120-second
  limit stopped with a feasible incumbent immediately before convergence.
- The default per-solve limit is 180 seconds. Time-limited incumbents remain
  unacceptable for confirmatory results.

## Protocol v5.1.29 rolling economic MIP gap

- Seal: `1D7B0490`; supersedes v5.1.28 seal `C3EC6E70` without relaxing any
  physical, contract, carbon, storage, sell, or curtailment constraint.
- The day-58 incumbent had a 0.0004212 relative gap after 60 seconds and
  5.26e-9 constraint violation, but did not meet 1e-4 before the time limit.
- Rolling 72-hour economic solves now use a 1e-3 relative gap and retain the
  1e-5 constraint tolerance. Annual baseline and contract-certificate solves
  remain at 1e-4.

## Protocol v5.1.30 dual economic carbon envelope

- Seal: `B0162658`; supersedes v5.1.29 seal `1D7B0490` without changing the final
  Zhou S2 annual-intensity equation or adding carbon slack.
- By day 362, 1.117 MtCO2 of cumulative debt could not be repaid by the maximum
  0.822 ktNH3 producible in the final 72 hours, although the scheduled absolute
  emissions budget was still satisfied.
- Economic-only now intersects its scheduled absolute budget with a physical
  maximum-remaining-HB-output reachability bound. The first controls early
  borrowing; the second preserves exact actual-NH3 year-end feasibility.

## Protocol v5.1.31 robust recovery envelope

- Seal: `4289A2F0`; supersedes v5.1.30 seal `B0162658` without modifying actual
  equipment capacity, production, emissions, or the year-end equation.
- The day-343 state retained only about 2.3% margin against a 100%-HB theoretical
  recovery bound; the following 72-hour physical model could not realize that
  optimistic maximum.
- Economic-only credits 90% of maximum remaining HB output in the intermediate
  recovery envelope, selected from the frozen 0.85/0.90/0.95/1.00 development
  sensitivity grid. No QI model is introduced.

## Protocol v5.1.32 common annual-output reachability

- Seal: `50F192B8`; supersedes v5.1.31 seal `4289A2F0` without adding daily
  contracts, FIFO delivery, equipment, or QI-model logic to economic-only.
- A fixed emissions budget based on 76022.964275 tNH3 was inconsistent with an
  economic comparator allowed to end near 67 ktNH3, making the final actual-NH3
  denominator unreachable despite satisfying the intermediate numerator cap.
- Both schemes now provide at least the frozen MAT annual output. Economic-only
  uses a 90%-derated physical remaining-output reachability check and a terminal
  annual quantity constraint; contract timing remains exclusive to the contract
  scheme.

## Protocol v5.1.33 cumulative annual-output pacing

- Seal: `D5D9A770`; supersedes v5.1.32 seal `50F192B8` without adding daily
  delivery cohorts or removing the common annual-output target.
- Remaining-capacity reachability postponed production until day 224, where the
  next 72-hour window needed 739.726 tNH3 and was physically infeasible.
- Economic-only has a seven-day startup grace period, then a linear cumulative
  minimum over the remaining 358 days. Early output banks toward the annual
  total, so this is annual service normalization rather than a daily contract.

## Protocol v5.1.34 commitment-boundary output pacing

- Seal: `C5D8CB20`; supersedes v5.1.33 seal `D5D9A770` without changing the annual
  output, carbon limit, equipment, or 24-hour commitment interval.
- At day 24, applying the cumulative schedule to all 72 forecast hours required
  482.9 tNH3 under a threefold persistence forecast and conflicted with the
  accrued carbon budget. The same schedule required only 58.25 t at the actual
  24-hour commitment boundary and was strictly feasible.
- Output pacing is now enforced on every committed daily boundary. The planning
  tail remains active for physical state foresight but cannot impose production
  that will be reforecast before execution; day 365 still closes the exact
  annual target.

## Protocol v5.1.35 constrained production reference governor

- Seal: `C7106EE0`; supersedes v5.1.34 seal `C5D8CB20` without changing equipment,
  the annual target, carbon budget, or final feasibility tests.
- At day 44, the cumulative schedule requested 212.35 tNH3 while the strict
  commitment feasible set could produce at most 139.38 t under the forecast,
  carbon, hydrogen, and grid constraints.
- An infeasible intermediate request is projected to maximum feasible committed
  output in both day-ahead and realtime layers. Unmet progress remains in the
  next cumulative request; the year-end target cannot be projected or relaxed.
- The phase-2 HB optimum is passed to phase 3 with a 1e-5 load-hour allowance,
  equal to the solver constraint tolerance. The former 1e-6 allowance produced
  a numerical false infeasibility at day 30 despite a 7.3e-12 feasible residual.

## Protocol v5.1.36 minimum-emissions carbon borrowing

- Seal: `EE4C6128`; supersedes v5.1.35 seal `C7106EE0` without changing the annual
  emissions budget, final actual-output intensity, or seven-day contract delay.
- At day 182, minimum physical operation emitted 227891.72 kgCO2 while the
  14-day schedule exposed only 68494.03 kgCO2. The 159397.68 kgCO2 shortfall was
  2.55099 days of accrual beyond the prior allowance.
- The economic-only borrowing window is 17 days, the smallest whole-day setting
  above the measured 16.55099-day requirement. Borrowing remains inside the
  fixed annual budget and must be repaid by year end.

## Protocol v5.1.37 development-oracle functional closure

- Seal: `000CDCA8`; supersedes v5.1.36 seal `EE4C6128` and restores the 14-day
  carbon borrowing rule.
- Three additional borrowing days were fully consumed before day 182, which
  reproduced the same binding-budget failure. Increasing the window therefore
  shifted the trajectory rather than restoring recursive feasibility.
- Existing usable H2 is 6.591 t versus 14.795 t for 24 hours of minimum HB load,
  so a full-day handoff reserve would require unapproved storage expansion.
- `observed_oracle` is restricted to 2022/2023 development years and provides a
  functional-closure/perfect-information upper bound only. It is forbidden for
  holdout claims; real forecasts continue through the unchanged table schema.
