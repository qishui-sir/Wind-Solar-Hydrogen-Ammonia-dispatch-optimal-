function tests = test_chose_index
if nargout == 0
    test_file = [mfilename('fullpath'), '.m'];
    results = runtests(test_file);
    assertSuccess(results);
    return
end
tests = functiontests(localfunctions);
end

function setupOnce(test_case)
test_case.TestData.study = runIndicatorSelectionStudy();
end

function testStep01DefineScope(test_case)
step = test_case.TestData.study.step01;

verifyTrue(test_case, step.complete);
verifyEqual(test_case, step.scope, ...
    "HB load and ammonia-product supply stability at hourly resolution");
verifyEqual(test_case, step.confirmatory_status, ...
    "protocol_locked_in_code_before_any_generated_data");
end

function testStep02BuildCandidateLedger(test_case)
step = test_case.TestData.study.step02;

verifyTrue(test_case, step.complete);
verifyEqual(test_case, height(step.registry), 17);
verifyEqual(test_case, numel(unique(step.registry.Family)), 5);
verifyEqual(test_case, numel(unique(step.registry.UpperDimension)), 3);
verifyEqual(test_case, numel(unique(step.registry.Name)), 17);
verifyFalse(test_case, any(ismissing(step.registry.Formula)));
verifyFalse(test_case, any(ismissing(step.registry.EngineeringAction)));
verifyEqual(test_case, height(step.test_catalog), 8);
verifyEqual(test_case, height(step.expected_response), 8 * 17);
verifyEqual(test_case, height(step.mandatory_tests), 17);
h2_margin = step.registry.Name == "h2_min_margin";
verifyFalse(test_case, step.registry.CoreEligible(h2_margin));
verifyEqual(test_case, step.registry.FunctionalPosition(h2_margin), ...
    "hard_constraint");
rms_ramp = step.registry.Name == "rms_ramp";
ramp_p95 = step.registry.Name == "ramp_p95";
verifyGreaterThan(test_case, step.registry.CorePreference(rms_ramp), ...
    step.registry.CorePreference(ramp_p95));
switch_count = step.registry.Name == "switch_count";
verifyEqual(test_case, step.registry.ThresholdOrigin(switch_count), ...
    "MILP_binary_state");
end

function testStep03SealProtocolBeforeTesting(test_case)
step = test_case.TestData.study.step03;

verifyTrue(test_case, step.complete);
verifyTrue(test_case, step.seal_verified);
verifyNotEmpty(test_case, step.protocol.Seal);
verifyEqual(test_case, step.protocol.ProtocolVersion, "4.0.0");
verifyEqual(test_case, numel(step.protocol.RandomRule.Features), 6);
verifyEqual(test_case, step.protocol.RandomRule.Design, ...
    "three_level_full_factorial");
verifyEqual(test_case, step.protocol.MonotonicityRule.Method, ...
    "partial_Spearman_on_ranks_controlling_other_five_factors");
verifyEqual(test_case, step.protocol.SelectionRule.HoldoutUsedForSelection, false);
verifyEqual(test_case, step.protocol.SelectionRule.MinimumCoreCount, 3);
verifyEqual(test_case, step.protocol.SelectionRule.MaximumCoreCount, 5);
verifyEqual(test_case, step.protocol.TieRule, ...
    "lexicographic_then_metric_name_ascending");
verifyTrue(test_case, isfield(step.protocol, 'EngineeringRule'));
verifyTrue(test_case, isfield(step.protocol, 'IncrementalInformationRule'));
end

function testStep04RunDeterministicKnownTruthTests(test_case)
step = test_case.TestData.study.step04;

verifyTrue(test_case, step.complete);
verifyEqual(test_case, numel(unique(step.audit.Test)), 8);
verifySize(test_case, step.functional_signature, [8, 17]);
end

function testStep05RunJointRandomBenchmark(test_case)
step = test_case.TestData.study.step05;

verifyTrue(test_case, step.complete);
verifyEqual(test_case, step.generator_type, ...
    "orthogonal_six_factor_full_factorial");
verifyEqual(test_case, height(step.factors), 3 ^ 6);
verifyEqual(test_case, width(step.factors), 6);
verifyEqual(test_case, height(step.effects), 17);
verifyLessThan(test_case, step.max_abs_factor_correlation, 1e-12);
verifyGreaterThanOrEqual(test_case, step.effects.CliffsDelta, -1);
verifyLessThanOrEqual(test_case, step.effects.CliffsDelta, 1);
verifyTrue(test_case, all(step.effects.CILow <= step.effects.CIHigh));
end

function testStep06BuildFeasibleEngineeringBenchmark(test_case)
step = test_case.TestData.study.step06;
config = test_case.TestData.study.step03.protocol.Config;

verifyTrue(test_case, step.complete);
verifyTrue(test_case, all(step.hb_on(:) == 0 | step.hb_on(:) == 1));
verifyEqual(test_case, step.load(step.hb_on == 0), ...
    zeros(nnz(step.hb_on == 0), 1), 'AbsTol', 1e-12);
verifyGreaterThanOrEqual(test_case, step.load(step.hb_on == 1), ...
    config.load_bounds(1));
verifyLessThanOrEqual(test_case, step.load(step.hb_on == 1), ...
    config.load_bounds(2));
verifyLessThanOrEqual(test_case, step.max_online_ramp, ...
    config.ramp_limit + 1e-12);
verifyGreaterThanOrEqual(test_case, step.h2_soc, 0);
verifyLessThanOrEqual(test_case, step.h2_soc, 1);
verifyLessThanOrEqual(test_case, abs(step.balance_residual), 1e-10);
verifyGreaterThanOrEqual(test_case, step.h2_production, 0);
end

function testStep07EvaluateValidity(test_case)
step = test_case.TestData.study.step07;

verifyTrue(test_case, step.complete);
verifyEqual(test_case, height(step.validity), 17);
verifyTrue(test_case, all(~step.validity.ValidityPass | ...
    step.validity.MandatoryDeterministicPass));
verifyGreaterThanOrEqual(test_case, ...
    step.validity.OtherApplicablePassRate, 0);
verifyLessThanOrEqual(test_case, ...
    step.validity.OtherApplicablePassRate, 1);
verifyGreaterThanOrEqual(test_case, step.validity.MonotonicityRho, -1);
verifyLessThanOrEqual(test_case, step.validity.MonotonicityRho, 1);
verifyEqual(test_case, unique(step.validity.MonotonicityMethod), ...
    "partial_Spearman");
verifyGreaterThanOrEqual(test_case, ...
    step.validity.ConditionalDirectionRate, 0);
verifyLessThanOrEqual(test_case, ...
    step.validity.ConditionalDirectionRate, 1);
verifyGreaterThanOrEqual(test_case, step.validity.SaturationRatio, 0);
end

function testStep08ScreenRedundancyAndIncrementalInformation(test_case)
step = test_case.TestData.study.step08;

verifyTrue(test_case, step.complete);
verifySize(test_case, step.pearson, [17, 17]);
verifySize(test_case, step.spearman, [17, 17]);
verifySize(test_case, step.normalized_mutual_information, [17, 17]);
verifySize(test_case, step.hierarchical_tree, [16, 3]);
verifyEqual(test_case, height(step.incremental_information), 17);
verifyGreaterThanOrEqual(test_case, ...
    step.incremental_information.IncrementalR2, 0);
if ~isempty(step.flagged_pairs)
    verifyTrue(test_case, all(step.flagged_pairs.MathematicallyRedundant | ...
        (step.flagged_pairs.StatisticallyRedundant & ...
        step.flagged_pairs.FunctionallyRedundant)));
end
end

function testStep09EvaluateRobustness(test_case)
step = test_case.TestData.study.step09;

verifyTrue(test_case, step.complete);
verifyGreaterThanOrEqual(test_case, step.results.KendallTau, -1);
verifyLessThanOrEqual(test_case, step.results.KendallTau, 1);
verifyGreaterThanOrEqual(test_case, step.results.BaselineTieRate, 0);
verifyLessThanOrEqual(test_case, step.results.BaselineTieRate, 1);
verifyGreaterThanOrEqual(test_case, step.results.TrialTieRate, 0);
verifyLessThanOrEqual(test_case, step.results.TrialTieRate, 1);
verifyGreaterThanOrEqual(test_case, step.results.PairwiseAgreement, 0);
verifyLessThanOrEqual(test_case, step.results.PairwiseAgreement, 1);
verifyEqual(test_case, sort(unique(step.results.Parameter)), sort(...
    ["h2_measurement_noise"; "load_measurement_noise"; ...
    "low_load_threshold"; "min_dwell_hours"; ...
    "tail_percentile"; "window_hours"]));
verifyEqual(test_case, unique(step.sensitivity_results.Parameter), ...
    "sampling_hours");
switch_row = step.summary.Name == "switch_count";
verifyTrue(test_case, step.summary.Robust(switch_row));
verifyEqual(test_case, step.summary.ApplicableSettingCount(switch_row), 0);
ramp_row = step.applicability.Metric == "ramp_p95";
verifyTrue(test_case, contains(...
    step.applicability.HardKendallParameters(ramp_row), ...
    "tail_percentile"));
verifyEqual(test_case, step.applicability.HardKendallParameters(...
    step.applicability.Metric == "switch_count"), ...
    "fixed_definition_no_adjustable_parameter");
end

function testStep10BuildEmpiricalReferenceRanges(test_case)
step = test_case.TestData.study.step10;

verifyTrue(test_case, step.complete);
verifyEqual(test_case, height(step.reference_ranges), 17);
verifyTrue(test_case, all(step.reference_ranges.P25 <= ...
    step.reference_ranges.P50));
verifyTrue(test_case, all(step.reference_ranges.P50 <= ...
    step.reference_ranges.P75));
verifyFalse(test_case, any(step.reference_ranges.IsUniversalStandard));
end

function testStep11MechanicallyLockCoreMetrics(test_case)
step = test_case.TestData.study.step11;
core = step.selection(step.selection.Decision == "core", :);

verifyTrue(test_case, step.complete);
verifyTrue(test_case, step.protocol_seal_verified);
verifyTrue(test_case, step.mechanical_rule_executed);
verifyTrue(test_case, step.prerequisites_complete);
verifyFalse(test_case, step.selection_uses_holdout);
verifyLessThanOrEqual(test_case, height(core), 5);
verifyEqual(test_case, numel(unique(core.Family)), height(core));
verifyEqual(test_case, step.selection_input_steps, "04-10");
if ~isempty(core)
    verifyEqual(test_case, ...
        numel(unique(core.UpperDimension)), 3);
end
if step.freeze_status == "insufficient_evidence_no_confirmatory_lock"
    verifyEmpty(test_case, core);
end
end

function testStep12ValidateOnIndependent2025Data(test_case)
step = test_case.TestData.study.step12;

verifyTrue(test_case, step.complete);
verifyFalse(test_case, step.used_for_selection);
verifyEqual(test_case, step.selection_hash_before, ...
    step.selection_hash_after);
if step.status == "ready_but_2025_holdout_manually_locked"
    verifyFalse(test_case, step.data_available);
    verifyFalse(test_case, step.holdout_authorized);
end
if step.data_available
    verifyEqual(test_case, step.data_year, 2025);
    verifyTrue(test_case, step.feasibility_pass);
    verifyGreaterThanOrEqual(test_case, step.sample_count, 1);
end
end

function testStep13BuildEngineeringResponseMap(test_case)
step = test_case.TestData.study.step13;

verifyTrue(test_case, step.complete);
verifyEqual(test_case, height(step.action_map), 17);
verifyFalse(test_case, any(ismissing(step.action_map.EngineeringAction)));
verifyFalse(test_case, any(ismissing(step.action_map.PotentialSideEffect)));
verifyFalse(test_case, any(ismissing(step.action_map.OptimizationMapping)));
verifyEqual(test_case, height(step.upper_dimension_audit), 3);
verifyEqual(test_case, height(step.metric_gate_audit), 17);
verifyEqual(test_case, height(step.gate_failure_summary), 9);
printSelectionSummary(test_case.TestData.study);
end

function study = runIndicatorSelectionStudy()
config = localConfig();
registry = buildCandidateRegistry();
test_catalog = buildDeterministicTestCatalog();
expected_response = buildExpectedResponseMatrix(registry, test_catalog);
mandatory_tests = buildMandatoryDeterministicTests();

step01 = defineScope();
step02 = buildCandidateLedger(registry, test_catalog, ...
    expected_response, mandatory_tests);
protocol = createFrozenProtocol(config, registry, test_catalog, ...
    expected_response, mandatory_tests);
step03 = sealProtocol(protocol);

step04 = runDeterministicKnownTruthTests(protocol);
step05 = runJointRandomBenchmark(protocol);
step06 = buildFeasibleEngineeringBenchmark(protocol);
step07 = evaluateValidity(protocol, step04, step05);
step08 = screenRedundancyAndIncrementalInformation(...
    protocol, step04, step05, step06);
step09 = evaluateParameterRobustness(protocol, step06);
step10 = buildReferenceRanges(protocol, step06.metrics);
step11 = mechanicallyLockCoreMetrics(protocol, step04, step05, ...
    step06, step07, step08, step09, step10);
step12 = validateOnIndependent2025Data(protocol, step11);
step13 = buildEngineeringResponseMap(...
    protocol, step11, step12, step08, step09);

study.step01 = step01;
study.step02 = step02;
study.step03 = step03;
study.step04 = step04;
study.step05 = step05;
study.step06 = step06;
study.step07 = step07;
study.step08 = step08;
study.step09 = step09;
study.step10 = step10;
study.step11 = step11;
study.step12 = step12;
study.step13 = step13;
end

function config = localConfig()
config.dt = 1;
config.window_hours = 24;
config.tail_percentile = 95;
config.min_dwell_hours = 4;
config.low_load_threshold = 0.40;
config.load_bounds = [0.30, 1.10];
config.ramp_limit = 0.20;
config.h2_safe = 0.20;
config.h2_capacity_hours = 12;
config.h2_conversion_efficiency = 0.95;
config.ael_h2_max = 1.40;

% These values are fixed before any generated schedule is evaluated.
config.effect_type = "Cliffs_delta_primary_Cohen_d_secondary";
config.cliffs_delta_threshold = 0.474;
config.effect_ci_lower_threshold = 0;
config.deterministic_pass_rate = 0.80;
config.monotonicity_threshold = 0.80;
config.saturation_ratio_threshold = 0.05;
config.pearson_redundancy = 0.90;
config.spearman_redundancy = 0.90;
config.nmi_redundancy = 0.80;
config.incremental_r2_threshold = 0.01;
config.kendall_threshold = 0.80;
config.minimum_interpretability = 2;
config.minimum_actionability = 2;
config.minimum_reproducibility = 2;
config.minimum_optimization_compatibility = 1;

config.random_seed = 20261129;
config.random_repetitions = 1;
config.random_samples_per_repetition = 3 ^ 6;
config.bootstrap_iterations = 300;
config.engineering_seed = 20262129;
config.engineering_schedule_count = 72;
config.engineering_days = 14;
config.holdout_seed = 20251129;
config.holdout_schedule_count = 64;
config.holdout_days_per_schedule = 14;
config.holdout_unlock_environment = "AMMONIA_OPEN_2025_HOLDOUT";
end

function step = defineScope()
step.scope = ...
    "HB load and ammonia-product supply stability at hourly resolution";
step.excluded_scope = ["AEL module lifetime as a direct stability target"; ...
    "Economic optimality as a stability metric"; ...
    "Universal good/bad thresholds before multi-scenario evidence"];
step.confirmatory_status = ...
    "protocol_locked_in_code_before_any_generated_data";
step.disclosure = "This in-code seal is an internal preregistration aid; " + ...
    "external confirmatory use still requires a timestamped registry.";
step.complete = strlength(step.scope) > 0 && ...
    numel(step.excluded_scope) == 3;
end

function registry = buildCandidateRegistry()
name = ["dcv_mean"; "dcv_p95"; "dcv_max"; "intraday_mad"; ...
    "daily_output_cv"; "daily_output_max_dev"; ...
    "daily_shortfall_p95"; "low_load_ratio"; "mar"; ...
    "rms_ramp"; "ramp_p95"; "ramp_max"; "switch_count"; ...
    "short_dwell_ratio"; "h2_soc_p05"; "h2_min_margin"; ...
    "h2_risk_hours"];
family = [repmat("amplitude", 4, 1); repmat("delivery", 4, 1); ...
    repmat("ramp", 4, 1); repmat("switching", 2, 1); ...
    repmat("hydrogen_security", 3, 1)];
upper_dimension = [repmat("output_stability", 8, 1); ...
    repmat("dynamic_stability", 6, 1); ...
    repmat("hydrogen_security", 3, 1)];
role = ["primary"; "tail"; "extreme"; "alternative"; ...
    "primary"; "extreme"; "tail"; "operating_state"; ...
    "primary"; "primary"; "tail_auxiliary"; "extreme"; ...
    "binary_state"; "dwell_state"; "statistical_core"; ...
    "hard_constraint"; "statistical_auxiliary"];
target_feature = [repmat("intraday_amplitude", 4, 1); ...
    repmat("interday_spread", 3, 1); "low_load_fraction"; ...
    repmat("ramp_intensity", 4, 1); ...
    repmat("switch_frequency", 2, 1); repmat("h2_stress", 3, 1)];
unit = [repmat("fraction", 8, 1); repmat("fraction/h", 4, 1); ...
    "events"; "fraction"; "fraction"; "fraction"; "h"];
larger_is_worse = [true(14, 1); false(2, 1); true];
formula = [
    "mean_d sqrt(mean_h((L-daily_mean)^2))";
    "P95_d sqrt(mean_h((L-daily_mean)^2))";
    "max_d sqrt(mean_h((L-daily_mean)^2))";
    "mean_d mean_h(abs(L-daily_mean))";
    "std(daily_output)/mean(daily_output)";
    "max(abs(daily_output-mean))/mean";
    "P95(max(mean_output-daily_output,0)/mean_output)";
    "online hours(L<low_load_threshold)/online hours";
    "mean online-to-online abs(diff(L))/dt";
    "RMS online-to-online abs(diff(L))/dt";
    "P95 online-to-online abs(diff(L))/dt";
    "max online-to-online abs(diff(L))/dt";
    "sum(abs(diff(HB_on)))";
    "hours in HB_on binary runs shorter than min_dwell/total hours";
    "P05(H2_SOC)";
    "min(H2_SOC-h2_safe)";
    "hours(H2_SOC<h2_safe)"];
source_class = [repmat("B+C", 4, 1); repmat("C", 4, 1); ...
    repmat("A+C", 4, 1); repmat("C", 2, 1); repmat("A+C", 3, 1)];
interpretability = [3; 3; 2; 3; 3; 2; 3; 3; 3; 2; 3; 3; ...
    3; 3; 3; 3; 3];
actionability = [3; 2; 2; 3; 3; 2; 3; 3; 3; 2; 3; 3; ...
    3; 3; 3; 3; 3];
reproducibility = repmat(3, 17, 1);
optimization_compatibility = [1; 1; 1; 3; 2; 2; 2; 3; 3; 2; ...
    1; 2; 3; 3; 1; 2; 3];

engineering_action = [
    "Use H2 buffering or constrain within-day load deviation";
    "Protect high-volatility days with reserve-aware scheduling";
    "Add an extreme-day operating safeguard";
    "Penalize absolute deviation from a daily load target";
    "Add daily or weekly cumulative production bands";
    "Limit the largest daily delivery deviation";
    "Add a lower-tail daily production requirement";
    "Reduce time spent below the efficient HB load region";
    "Penalize total absolute load variation";
    "Reduce repeated medium-to-large ramps";
    "Add ramp-risk limits or staged transitions";
    "Enforce the physical maximum ramp constraint";
    "Add switching cost, hysteresis, or an event budget";
    "Add minimum dwell constraints";
    "Maintain a forecast-aware H2 reserve target";
    "Increase reserve margin or storage capacity";
    "Eliminate reserve violations using robust scheduling"];
side_effect = [
    "May increase storage use, curtailment, or grid purchases";
    "May reduce profit on rare high-value days";
    "May be dominated by a single outlier";
    "May suppress economically useful load movement";
    "May reduce intraday dispatch freedom";
    "May overreact to one abnormal day";
    "May require extra grid energy or storage";
    "May increase grid purchases or renewable curtailment";
    "May reduce renewable tracking and profit";
    "May increase curtailment or storage cycling";
    "May delay response to persistent renewable surplus";
    "May require more H2 buffering";
    "May sacrifice arbitrage and renewable utilization";
    "May delay necessary corrective switching";
    "May increase grid purchases or curtailment";
    "May require additional storage investment";
    "May make the schedule conservative"];
optimization_mapping = [
    "Report metric; use MAD as a MILP proxy";
    "Scenario tail constraint or CVaR proxy";
    "Worst-day constraint";
    "Linear absolute-deviation variables";
    "Daily cumulative production constraint";
    "Daily deviation epigraph";
    "Lower-tail production constraint";
    "Binary low-load indicators or piecewise penalty";
    "Linear total-variation penalty";
    "Quadratic or piecewise-linear ramp penalty";
    "Quantile proxy or ramp-risk budget";
    "Hard ramp constraint";
    "MILP HB binary state-change variables";
    "Minimum dwell constraints";
    "Terminal and rolling reserve constraints";
    "Minimum inventory margin constraint";
    "Reserve violation or CVaR constraint"];

functional_position = role;
core_eligible = true(17, 1);
core_eligible(name == "h2_min_margin") = false;
core_preference = ones(17, 1);
core_preference(name == "rms_ramp" | name == "h2_soc_p05") = 3;
core_preference(name == "ramp_p95" | name == "h2_risk_hours") = 1;
threshold_origin = repmat("not_applicable", 17, 1);
threshold_origin(name == "low_load_ratio") = "empirical_engineering";
threshold_origin(name == "short_dwell_ratio") = "empirical_engineering";
threshold_origin(name == "switch_count") = "MILP_binary_state";
threshold_origin(name == "h2_min_margin" | name == "h2_risk_hours") = ...
    "physical_safety_limit";

registry = table(name, family, upper_dimension, role, functional_position, ...
    core_eligible, core_preference, target_feature, unit, ...
    larger_is_worse, formula, source_class, interpretability, ...
    actionability, reproducibility, optimization_compatibility, ...
    threshold_origin, engineering_action, side_effect, ...
    optimization_mapping, ...
    'VariableNames', {'Name', 'Family', 'UpperDimension', 'Role', ...
    'FunctionalPosition', 'CoreEligible', 'CorePreference', 'TargetFeature', ...
    'Unit', 'LargerIsWorse', 'Formula', 'SourceClass', ...
    'InterpretabilityScore', 'ActionabilityScore', ...
    'ReproducibilityScore', 'OptimizationCompatibilityScore', ...
    'ThresholdOrigin', 'EngineeringAction', 'PotentialSideEffect', ...
    'OptimizationMapping'});
end

function catalog = buildDeterministicTestCatalog()
name = ["constant"; "single_step"; "single_spike"; ...
    "high_frequency_oscillation"; "low_frequency_periodic"; ...
    "monotonic_drift"; "long_low_load"; ...
    "equal_daily_output_different_order"];
definition = [
    "Constant 65% HB load with safe H2 reserve";
    "One 55%-to-75% step aligned to a day boundary";
    "One-hour 80% spike from a 65% baseline";
    "Blocked versus frequent HB on/off states with equal daily on-hours";
    "48-hour smooth sinusoid around 65% load";
    "Monotonic 50%-to-80% drift over fourteen days";
    "Four low-load days and ten compensating high-load days";
    "Blocked and alternating hours with identical daily histograms"];
theoretical_expectation = [
    "All load-variation metrics attain their mathematical minima";
    "Delivery and one-transition ramp metrics respond; DCV remains zero";
    "Extreme amplitude, ramp, and short-state metrics respond";
    "Binary switching metrics respond while daily output remains unchanged";
    "Smooth amplitude and ramp metrics respond without switch events";
    "Slow-trend metrics respond without threshold switch events";
    "Delivery and low-load exposure metrics respond strongly";
    "Order-sensitive metrics differ; distribution-only metrics agree"];
catalog = table(name, definition, theoretical_expectation, ...
    'VariableNames', {'Name', 'Definition', 'TheoreticalExpectation'});
end

function mandatory = buildMandatoryDeterministicTests()
metric = ["dcv_mean"; "dcv_p95"; "dcv_max"; "intraday_mad"; ...
    "daily_output_cv"; "daily_output_max_dev"; ...
    "daily_shortfall_p95"; "low_load_ratio"; "mar"; ...
    "rms_ramp"; "ramp_p95"; "ramp_max"; "switch_count"; ...
    "short_dwell_ratio"; "h2_soc_p05"; "h2_min_margin"; ...
    "h2_risk_hours"];
test = ["low_frequency_periodic"; "single_spike"; ...
    "single_spike"; "low_frequency_periodic"; ...
    "single_step"; "single_step"; "long_low_load"; ...
    "long_low_load"; "equal_daily_output_different_order"; ...
    "equal_daily_output_different_order"; ...
    "low_frequency_periodic"; "single_spike"; ...
    "high_frequency_oscillation"; "high_frequency_oscillation"; ...
    "h2_security"; "h2_security"; "h2_security"];
rationale = [
    "Must detect sustained within-day amplitude";
    "Must detect a tail-day amplitude event";
    "Must detect the largest amplitude event";
    "Must detect distribution-wide within-day deviation";
    "Must detect between-day delivery variation";
    "Must detect the largest daily delivery deviation";
    "Must detect repeated low-delivery days";
    "Must detect prolonged low-load exposure";
    "Must detect order-induced total variation";
    "Must detect order-induced RMS ramping";
    "Must detect broadly distributed smooth ramps";
    "Must detect a physical extreme ramp";
    "Must detect frequent HB binary-state transitions";
    "Must detect repeated short operating states";
    "Must decrease when H2 reserve deteriorates";
    "Must decrease when minimum reserve margin deteriorates";
    "Must increase when reserve violations occur"];
mandatory = table(metric, test, rationale, ...
    'VariableNames', {'Metric', 'Test', 'Rationale'});
end

function expected = buildExpectedResponseMatrix(registry, catalog)
test_name = repelem(catalog.Name, height(registry));
metric_name = repmat(registry.Name, height(catalog), 1);
response = repmat("not_inferable", numel(test_name), 1);
expected = table(test_name, metric_name, response, ...
    'VariableNames', {'Test', 'Metric', 'Expected'});

load_metrics = registry.Name(~startsWith(registry.Name, "h2_"));
expected = setExpected(expected, "constant", load_metrics, "zero");
expected = setExpected(expected, "constant", "h2_risk_hours", "zero");
expected = setExpected(expected, "constant", ...
    ["h2_soc_p05"; "h2_min_margin"], "positive");

amplitude = registry.Name(registry.Family == "amplitude");
delivery = registry.Name(registry.Family == "delivery");
ramp = registry.Name(registry.Family == "ramp");
switching = registry.Name(registry.Family == "switching");
h2 = registry.Name(registry.Family == "hydrogen_security");

expected = setExpected(expected, "single_step", amplitude, "invariant");
expected = setExpected(expected, "single_step", delivery(1:3), "increase");
expected = setExpected(expected, "single_step", "low_load_ratio", "invariant");
expected = setExpected(expected, "single_step", ...
    ["mar"; "rms_ramp"; "ramp_max"], "increase");
expected = setExpected(expected, "single_step", "ramp_p95", "invariant");
expected = setExpected(expected, "single_step", switching, "invariant");
expected = setExpected(expected, "single_step", h2, "invariant");

expected = setExpected(expected, "single_spike", amplitude, "increase");
expected = setExpected(expected, "single_spike", delivery(1:3), "increase");
expected = setExpected(expected, "single_spike", "low_load_ratio", "invariant");
expected = setExpected(expected, "single_spike", ...
    ["mar"; "rms_ramp"; "ramp_max"], "increase");
expected = setExpected(expected, "single_spike", "ramp_p95", "invariant");
expected = setExpected(expected, "single_spike", switching, "invariant");
expected = setExpected(expected, "single_spike", h2, "invariant");

expected = setExpected(expected, "high_frequency_oscillation", ...
    amplitude, "invariant");
expected = setExpected(expected, "high_frequency_oscillation", ...
    delivery, "invariant");
expected = setExpected(expected, "high_frequency_oscillation", ...
    ramp, "invariant");
expected = setExpected(expected, "high_frequency_oscillation", ...
    switching, "increase");
expected = setExpected(expected, "high_frequency_oscillation", ...
    h2, "invariant");

expected = setExpected(expected, "low_frequency_periodic", ...
    amplitude, "increase");
expected = setExpected(expected, "low_frequency_periodic", ...
    delivery(1:3), "increase");
expected = setExpected(expected, "low_frequency_periodic", ...
    "low_load_ratio", "invariant");
expected = setExpected(expected, "low_frequency_periodic", ramp, "increase");
expected = setExpected(expected, "low_frequency_periodic", ...
    "switch_count", "invariant");
expected = setExpected(expected, "low_frequency_periodic", h2, "invariant");

expected = setExpected(expected, "monotonic_drift", amplitude, "increase");
expected = setExpected(expected, "monotonic_drift", delivery(1:3), "increase");
expected = setExpected(expected, "monotonic_drift", ...
    "low_load_ratio", "invariant");
expected = setExpected(expected, "monotonic_drift", ramp, "increase");
expected = setExpected(expected, "monotonic_drift", switching, "invariant");
expected = setExpected(expected, "monotonic_drift", h2, "invariant");

expected = setExpected(expected, "long_low_load", amplitude, "invariant");
expected = setExpected(expected, "long_low_load", delivery, "increase");
expected = setExpected(expected, "long_low_load", ...
    ["mar"; "rms_ramp"; "ramp_max"], "increase");
expected = setExpected(expected, "long_low_load", ...
    "ramp_p95", "invariant");
expected = setExpected(expected, "long_low_load", ...
    switching, "invariant");
expected = setExpected(expected, "long_low_load", h2, "invariant");

order_test = "equal_daily_output_different_order";
expected = setExpected(expected, order_test, amplitude, "invariant");
expected = setExpected(expected, order_test, delivery, "invariant");
expected = setExpected(expected, order_test, ...
    ["mar"; "rms_ramp"], "increase");
expected = setExpected(expected, order_test, ...
    "ramp_p95", "increase");
expected = setExpected(expected, order_test, ...
    "ramp_max", "invariant");
expected = setExpected(expected, order_test, switching, "invariant");
expected = setExpected(expected, order_test, h2, "invariant");
end

function expected = setExpected(expected, test_name, metrics, response)
rows = expected.Test == test_name & ismember(expected.Metric, metrics);
expected.Expected(rows) = response;
end

function step = buildCandidateLedger(registry, catalog, expected, mandatory)
step.registry = registry;
step.test_catalog = catalog;
step.expected_response = expected;
step.mandatory_tests = mandatory;
step.source_classes = table(["A"; "B"; "C"; "D"], ...
    ["physical/model limit"; "published benchmark"; ...
    "empirical engineering range"; "unresolved/no universal range"], ...
    'VariableNames', {'Class', 'Meaning'});
step.complete = height(registry) == 17 && ...
    height(catalog) == 8 && height(expected) == 8 * 17 && ...
    height(mandatory) == height(registry) && ...
    all(ismember(mandatory.Metric, registry.Name)) && ...
    ~any(ismissing(registry.Formula)) && ...
    ~any(ismissing(expected.Expected));
end

function protocol = createFrozenProtocol(...
        config, registry, catalog, expected, mandatory)
protocol.ProtocolVersion = "4.0.0";
protocol.Config = config;
protocol.Registry = registry;
protocol.DeterministicTests = catalog;
protocol.ExpectedResponse = expected;
protocol.MandatoryDeterministicTests = mandatory;
protocol.RandomRule = struct(...
    'Generator', "orthogonal_six_factor_feasibility_aware", ...
    'Design', "three_level_full_factorial", ...
    'Features', ["intraday_amplitude"; "interday_spread"; ...
    "ramp_intensity"; "switch_frequency"; ...
    "low_load_fraction"; "h2_stress"], ...
    'Levels', [0, 0.5, 1], ...
    'SampleSize', config.random_samples_per_repetition, ...
    'SeedRule', "new_seed_shuffles_full_factorial_rows_only", ...
    'Strata', "all 3^5 fixed-nontarget combinations", ...
    'ForcingRule', "one fixed forcing vector shared by all 729 schedules");
protocol.MonotonicityRule = struct(...
    'Method', "partial_Spearman_on_ranks_controlling_other_five_factors", ...
    'TargetRule', "each metric is tested only against Registry.TargetFeature", ...
    'ConditionalDiagnostic', "high-versus-low direction rate within every " + ...
        "fixed combination of the other five factors", ...
    'Threshold', config.monotonicity_threshold);
protocol.EffectRule = struct(...
    'Primary', "Cliffs_delta", ...
    'Secondary', "unpaired_Cohen_d_report_only", ...
    'CliffsThreshold', config.cliffs_delta_threshold, ...
    'BootstrapIterations', config.bootstrap_iterations, ...
    'PassRule', "correct direction AND delta threshold AND " + ...
        "bootstrap CI lower > 0; Cohen d is not a gate");
protocol.RedundancyRule = struct(...
    'Mathematical', "strict identity or strict monotonic transform", ...
    'Statistical', "abs(Pearson)>=0.90 AND abs(Spearman)>=0.90 " + ...
        "AND normalized MI>=0.80", ...
    'Functional', "identical preregistered and observed response signatures", ...
    'Deletion', "delete only when mathematical redundancy is proved OR " + ...
        "statistical and functional redundancy both pass; hard constraints " + ...
        "and different functional positions do not compete for deletion");
protocol.IncrementalInformationRule = struct(...
    'Threshold', config.incremental_r2_threshold, ...
    'PassRule', "functionally unique OR cross-validated incremental R2 " + ...
        ">= 0.01 OR retained representative of a redundancy group; " + ...
        "incremental information governs additions, not whether a " + ...
        "redundancy group has any representative");
protocol.EngineeringRule = struct(...
    'MinimumInterpretability', config.minimum_interpretability, ...
    'MinimumActionability', config.minimum_actionability, ...
    'MinimumReproducibility', config.minimum_reproducibility, ...
    'MinimumOptimizationCompatibility', ...
        config.minimum_optimization_compatibility, ...
    'PassRule', "all four engineering minima must pass; no compensation");
protocol.MathematicalPairs = table(strings(0, 1), strings(0, 1), ...
    strings(0, 1), 'VariableNames', ...
    {'FirstMetric', 'SecondMetric', 'Proof'});
protocol.RobustnessGrid = buildV4RobustnessGrid(registry);
protocol.SensitivityGrid = buildSensitivityGrid(registry);
protocol.RobustnessApplicability = buildRobustnessApplicability(registry);
protocol.SelectionRule = struct(...
    'MinimumCoreCount', 3, ...
    'MaximumCoreCount', 5, ...
    'MaximumPerFamily', 1, ...
    'RequiredUpperDimensions', ["output_stability"; ...
        "dynamic_stability"; "hydrogen_security"], ...
    'IncrementalR2Threshold', config.incremental_r2_threshold, ...
    'HoldoutUsedForSelection', false, ...
    'EligibilityRule', "all mandatory deterministic tests pass AND " + ...
        "other applicable pass rate >= 0.80 AND Cliff delta gate passes " + ...
        "AND direction-standardized Spearman gate passes AND " + ...
        "family-applicable Kendall gate passes AND all explicit " + ...
        "engineering rules pass AND not redundant " + ...
        "AND (functionally unique OR incremental R2 >= 0.01) AND " + ...
        "the metric is preregistered as core eligible", ...
    'StopRule', "lock only after selecting at least one eligible metric " + ...
        "from each of output stability, dynamic stability, and hydrogen " + ...
        "security; retain at most one per family and at most five total", ...
    'ConflictPriority', ["validity gates"; "upper-dimension coverage"; ...
        "core functional-position preference"; "functional coverage"; ...
        "incremental R2"; "worst robustness"; ...
        "effect CI lower bound"; "engineering score"; ...
        "metric name ascending"]);
protocol.TieRule = "lexicographic_then_metric_name_ascending";
protocol.HoldoutRule = struct(...
    'Year', 2025, ...
    'Purpose', "validation_only_after_V4_development_gate_and_core_lock", ...
    'UnlockEnvironment', config.holdout_unlock_environment, ...
    'FailureAction', "retain locked set but label not independently confirmed");
protocol.DevelopmentDisclosure = "V4 was specified after reviewing V3. " + ...
    "It keeps every numerical gate unchanged, replaces coupled LHS samples " + ...
    "with a six-factor orthogonal full factorial, uses explicit HB binary " + ...
    "states, applies only definition-matched robustness gates, uses new " + ...
    "seeds, and keeps 2025 locked.";
protocol.Seal = protocolChecksum(protocol);
end

function grid = buildSensitivityGrid(registry)
parameter = "sampling_hours";
values = "1,2";
metrics = strjoin(registry.Name, ',');
grid = table(parameter, values, metrics, ...
    'VariableNames', {'Parameter', 'Values', 'Metrics'});
end

function grid = buildV4RobustnessGrid(registry)
parameter = ["load_measurement_noise"; "h2_measurement_noise"; ...
    "tail_percentile"; "window_hours"; "low_load_threshold"; ...
    "min_dwell_hours"];
values = ["0,0.0025,0.005"; "0,0.0025,0.005"; "90,95,99"; ...
    "12,24,48"; "0.35,0.40,0.45"; "2,4,6"];
metrics = [
    strjoin(registry.Name(registry.Family ~= "hydrogen_security" & ...
        registry.Family ~= "switching"), ',');
    strjoin(registry.Name(registry.Family == "hydrogen_security"), ',');
    "dcv_p95,daily_shortfall_p95,ramp_p95,h2_soc_p05";
    strjoin(registry.Name(registry.Family == "amplitude"), ',');
    "low_load_ratio";
    "short_dwell_ratio"];
grid = table(parameter, values, metrics, ...
    'VariableNames', {'Parameter', 'Values', 'Metrics'});
end

function applicability = buildRobustnessApplicability(registry)
parameters = repmat("fixed_definition_no_adjustable_parameter", ...
    height(registry), 1);
for metric_index = 1:height(registry)
    name = registry.Name(metric_index);
    family = registry.Family(metric_index);
    applicable = strings(0, 1);
    if family ~= "hydrogen_security" && family ~= "switching"
        applicable(end + 1, 1) = "load_measurement_noise"; %#ok<AGROW>
    elseif family == "hydrogen_security"
        applicable(end + 1, 1) = "h2_measurement_noise"; %#ok<AGROW>
    end
    if ismember(name, ["dcv_p95"; "daily_shortfall_p95"; ...
            "ramp_p95"; "h2_soc_p05"])
        applicable(end + 1, 1) = "tail_percentile"; %#ok<AGROW>
    end
    if family == "amplitude"
        applicable(end + 1, 1) = "window_hours"; %#ok<AGROW>
    end
    if name == "low_load_ratio"
        applicable(end + 1, 1) = "low_load_threshold"; %#ok<AGROW>
    elseif name == "short_dwell_ratio"
        applicable(end + 1, 1) = "min_dwell_hours"; %#ok<AGROW>
    end
    if ~isempty(applicable)
        parameters(metric_index) = strjoin(applicable, ',');
    end
end
sampling_role = repmat("diagnostic_only_fixed_at_1_hour", ...
    height(registry), 1);
applicability = table(registry.Name, parameters, sampling_role, ...
    registry.ThresholdOrigin, 'VariableNames', {'Metric', ...
    'HardKendallParameters', 'SamplingScaleRole', 'ThresholdOrigin'});
end

function step = sealProtocol(protocol)
step.protocol = protocol;
step.seal_verified = verifyProtocolSeal(protocol);
step.frozen_items = ["17 metrics and formulas"; ...
    "metric direction"; "three upper dimensions"; ...
    "8 deterministic tests"; "mandatory metric-test mapping"; ...
    "theoretical response matrix"; "random size and seed rule"; ...
    "effect type and thresholds"; "redundancy rule"; ...
    "conflict priority"; "robustness applicability matrix"; ...
    "functional positions and core eligibility"; "robustness grid"; ...
    "final count and stop rule"; "tie rule"; ...
    "2025 holdout exclusion from selection"];
step.complete = step.seal_verified && numel(step.frozen_items) == 16;
end

function is_valid = verifyProtocolSeal(protocol)
stored_seal = protocol.Seal;
protocol = rmfield(protocol, 'Seal');
is_valid = stored_seal == protocolChecksum(protocol);
end

function checksum = protocolChecksum(protocol)
if isfield(protocol, 'Seal')
    protocol = rmfield(protocol, 'Seal');
end
bytes = uint8(jsonencode(protocol));
hash_value = uint64(2166136261);
modulus = uint64(4294967296);
for byte_index = 1:numel(bytes)
    hash_value = bitxor(hash_value, uint64(bytes(byte_index)));
    hash_value = mod(hash_value * uint64(16777619), modulus);
end
checksum = string(sprintf('%08X', uint32(hash_value)));
end

function step = runDeterministicKnownTruthTests(protocol)
registry = protocol.Registry;
config = protocol.Config;
expected = protocol.ExpectedResponse;
[signals, h2_security] = buildDeterministicSignals(config);

test_name = strings(0, 1);
metric_name = strings(0, 1);
expected_response = strings(0, 1);
observed_response = strings(0, 1);
value_a = zeros(0, 1);
value_b = zeros(0, 1);
pass = false(0, 1);
signature = zeros(height(protocol.DeterministicTests), height(registry));

for test_index = 1:height(protocol.DeterministicTests)
    name = protocol.DeterministicTests.Name(test_index);
    signal = signals.(char(name));
    first = metricVector(signal.load_a, signal.h2_a, ...
        signal.hb_on_a, registry, config);
    second = metricVector(signal.load_b, signal.h2_b, ...
        signal.hb_on_b, registry, config);
    signature(test_index, :) = responseSignature(first, second);

    rows = expected.Test == name & expected.Expected ~= "not_inferable";
    expected_rows = expected(rows, :);
    for row_index = 1:height(expected_rows)
        metric_index = find(registry.Name == ...
            expected_rows.Metric(row_index), 1);
        actual = classifyResponse(name, first(metric_index), ...
            second(metric_index));
        test_name(end + 1, 1) = name; %#ok<AGROW>
        metric_name(end + 1, 1) = registry.Name(metric_index); %#ok<AGROW>
        expected_response(end + 1, 1) = ...
            expected_rows.Expected(row_index); %#ok<AGROW>
        observed_response(end + 1, 1) = actual; %#ok<AGROW>
        value_a(end + 1, 1) = first(metric_index); %#ok<AGROW>
        value_b(end + 1, 1) = second(metric_index); %#ok<AGROW>
        pass(end + 1, 1) = ...
            responseMatches(actual, expected_rows.Expected(row_index)); %#ok<AGROW>
    end
end

first_h2 = metricVector(h2_security.load_a, h2_security.h2_a, ...
    h2_security.hb_on_a, registry, config);
second_h2 = metricVector(h2_security.load_b, h2_security.h2_b, ...
    h2_security.hb_on_b, registry, config);
h2_metric = ["dcv_mean"; "h2_soc_p05"; ...
    "h2_min_margin"; "h2_risk_hours"];
h2_expected = ["invariant"; "decrease"; "decrease"; "increase"];
h2_observed = strings(numel(h2_metric), 1);
h2_pass = false(numel(h2_metric), 1);
h2_reference_value = zeros(numel(h2_metric), 1);
h2_test_value = zeros(numel(h2_metric), 1);
for metric_index = 1:numel(h2_metric)
    registry_index = find(registry.Name == h2_metric(metric_index), 1);
    h2_reference_value(metric_index) = first_h2(registry_index);
    h2_test_value(metric_index) = second_h2(registry_index);
    h2_observed(metric_index) = classifyResponse("h2_security", ...
        first_h2(registry_index), second_h2(registry_index));
    h2_pass(metric_index) = responseMatches(...
        h2_observed(metric_index), h2_expected(metric_index));
end

step.audit = table(test_name, metric_name, expected_response, ...
    observed_response, value_a, value_b, pass, 'VariableNames', ...
    {'Test', 'Metric', 'Expected', 'Observed', ...
    'ReferenceValue', 'TestValue', 'Pass'});
h2_test_name = repmat("h2_security", numel(h2_metric), 1);
step.h2_security_audit = table(h2_test_name, h2_metric, h2_expected, ...
    h2_observed, h2_reference_value, h2_test_value, h2_pass, ...
    'VariableNames', {'Test', 'Metric', 'Expected', 'Observed', ...
    'ReferenceValue', 'TestValue', 'Pass'});
step.functional_signature = signature;
step.complete = numel(unique(step.audit.Test)) == 8 && ...
    height(step.h2_security_audit) == 4 && ...
    ~any(ismissing(step.audit.Expected)) && ...
    ~any(ismissing(step.h2_security_audit.Expected));
end

function [signals, h2_security] = buildDeterministicSignals(~)
sample_count = 14 * 24;
safe_h2 = 0.60 * ones(sample_count, 1);
baseline = 0.65 * ones(sample_count, 1);

signals.constant = signalPair(baseline, baseline, safe_h2, safe_h2);

step_load = [0.55 * ones(7 * 24, 1); 0.75 * ones(7 * 24, 1)];
signals.single_step = signalPair(baseline, step_load, safe_h2, safe_h2);

spike_load = baseline;
spike_load(7 * 24 + 12) = 0.80;
signals.single_spike = signalPair(baseline, spike_load, safe_h2, safe_h2);

    blocked_state = repmat([ones(18, 1); zeros(6, 1)], 14, 1);
    high_frequency_state = repmat([1; 1; 1; 0], sample_count / 4, 1);
    blocked_load = 0.65 * blocked_state;
    high_frequency = 0.65 * high_frequency_state;
    signals.high_frequency_oscillation = signalPair(...
        blocked_load, high_frequency, safe_h2, safe_h2, ...
        blocked_state, high_frequency_state);

time = (0:(sample_count - 1))';
low_frequency = 0.65 + 0.12 * sin(2 * pi * time / 48);
signals.low_frequency_periodic = signalPair(...
    baseline, low_frequency, safe_h2, safe_h2);

drift = linspace(0.50, 0.80, sample_count)';
signals.monotonic_drift = signalPair(...
    baseline, drift, safe_h2, safe_h2);

high_compensation = (14 * 0.65 - 4 * 0.32) / 10;
low_load = [0.32 * ones(4 * 24, 1); ...
    high_compensation * ones(10 * 24, 1)];
signals.long_low_load = signalPair(...
    baseline, low_load, safe_h2, safe_h2);

blocked = repmat([0.55 * ones(12, 1); 0.75 * ones(12, 1)], 14, 1);
alternating = repmat([0.55; 0.75], sample_count / 2, 1);
signals.equal_daily_output_different_order = signalPair(...
    blocked, alternating, safe_h2, safe_h2);

risky_h2 = linspace(0.55, 0.05, sample_count)';
h2_security = signalPair(baseline, baseline, safe_h2, risky_h2);
end

function pair = signalPair(load_a, load_b, h2_a, h2_b, hb_on_a, hb_on_b)
if nargin < 6
    hb_on_a = ones(size(load_a));
    hb_on_b = ones(size(load_b));
end
pair.load_a = load_a;
pair.load_b = load_b;
pair.h2_a = h2_a;
pair.h2_b = h2_b;
pair.hb_on_a = hb_on_a;
pair.hb_on_b = hb_on_b;
end

function signature = responseSignature(first, second)
tolerance = 1e-10 * (1 + max(abs([first; second]), [], 1));
signature = sign(second - first);
signature(abs(second - first) <= tolerance) = 0;
end

function response = classifyResponse(test_name, first, second)
tolerance = 1e-10 * (1 + max(abs([first, second])));
if test_name == "constant"
    if abs(second) <= tolerance
        response = "zero";
    elseif second > tolerance
        response = "positive";
    else
        response = "negative";
    end
elseif abs(second - first) <= tolerance
    response = "invariant";
elseif second > first
    response = "increase";
else
    response = "decrease";
end
end

function pass = responseMatches(observed, expected)
pass = observed == expected;
end

function step = runJointRandomBenchmark(protocol)
config = protocol.Config;
registry = protocol.Registry;
[factors, repetition] = generateOrthogonalFactorMatrix(config.random_seed);
shared_forcing = generatedForcing(config.engineering_days * 24, 1, 1);
forcing_bank = repmat(shared_forcing, 1, height(factors));
[metrics, feasibility] = evaluateFactorSchedules(...
    factors, repetition, forcing_bank, protocol);
effects = evaluateFactorEffects(metrics, factors, repetition, ...
    registry, config, config.bootstrap_iterations);

factor_correlation = corr(table2array(factors), 'Rows', 'pairwise');
factor_correlation(1:(width(factors) + 1):end) = 0;
max_abs_factor_correlation = max(abs(factor_correlation), [], 'all');

step.factors = factors;
step.repetition = repetition;
step.metrics = metrics;
step.effects = effects;
step.feasibility = feasibility;
step.factor_correlation = factor_correlation;
step.max_abs_factor_correlation = max_abs_factor_correlation;
step.generator_type = "orthogonal_six_factor_full_factorial";
step.monotonicity_method = protocol.MonotonicityRule.Method;
step.perfect_separation_count = sum(abs(effects.CliffsDelta) > 0.999);
step.complete = feasibility.Pass && ...
    all(isfinite(effects.CliffsDelta)) && ...
    all(isfinite(effects.CILow)) && all(isfinite(effects.CIHigh)) && ...
    height(factors) == 3 ^ 6 && max_abs_factor_correlation < 1e-12;
end

function [factors, repetition] = generateOrthogonalFactorMatrix(seed)
levels = [0, 0.5, 1];
[f1, f2, f3, f4, f5, f6] = ndgrid(...
    levels, levels, levels, levels, levels, levels);
values = [f1(:), f2(:), f3(:), f4(:), f5(:), f6(:)];
old_random_state = rng;
random_cleanup = onCleanup(@() rng(old_random_state));
rng(seed, 'twister');
values = values(randperm(size(values, 1)), :);
feature_names = ["intraday_amplitude"; "interday_spread"; ...
    "ramp_intensity"; "switch_frequency"; ...
    "low_load_fraction"; "h2_stress"];
factors = array2table(values, 'VariableNames', cellstr(feature_names));
repetition = ones(size(values, 1), 1);
end

function [factors, repetition] = generateFactorMatrix(...
        base_seed, repetition_count, samples_per_repetition)
feature_names = ["intraday_amplitude"; "interday_spread"; ...
    "ramp_intensity"; "switch_frequency"; ...
    "low_load_fraction"; "h2_stress"];
total_count = repetition_count * samples_per_repetition;
values = zeros(total_count, numel(feature_names));
repetition = zeros(total_count, 1);
old_random_state = rng;
random_cleanup = onCleanup(@() rng(old_random_state));

row = 0;
for repetition_index = 1:repetition_count
    rng(base_seed + 1009 * (repetition_index - 1), 'twister');
    block = stratifiedUnitSample(samples_per_repetition, ...
        numel(feature_names));
    rows = (row + 1):(row + samples_per_repetition);
    values(rows, :) = block;
    repetition(rows) = repetition_index;
    row = row + samples_per_repetition;
end
factors = array2table(values, 'VariableNames', cellstr(feature_names));
end

function sample = stratifiedUnitSample(sample_count, dimension_count)
sample = zeros(sample_count, dimension_count);
for dimension = 1:dimension_count
    sample(:, dimension) = ((0:(sample_count - 1))' + rand(sample_count, 1)) ...
        / sample_count;
    sample(:, dimension) = sample(randperm(sample_count), dimension);
end
end

function [metrics, feasibility] = evaluateFactorSchedules(...
        factors, repetition, forcing_bank, protocol)
registry = protocol.Registry;
config = protocol.Config;
schedule_count = height(factors);
metric_values = zeros(schedule_count, height(registry));
max_ramp = 0;
max_balance_residual = 0;
minimum_soc = 1;
maximum_soc = 0;
minimum_online_load = inf;
maximum_online_load = -inf;
off_load_error = 0;

for schedule_index = 1:schedule_count
    if isempty(forcing_bank)
        forcing = generatedForcing(config.engineering_days * 24, ...
            schedule_index, repetition(schedule_index));
    else
        forcing = forcing_bank(:, schedule_index);
    end
    factor_row = table2array(factors(schedule_index, :));
    schedule = generateFeasibleSchedule(factor_row, forcing, config);
    metric_values(schedule_index, :) = metricVector(...
        schedule.load, schedule.h2_soc(2:end), schedule.hb_on, ...
        registry, config);
    online_ramp = onlineRampValues(...
        schedule.load, schedule.hb_on, config.dt);
    max_ramp = max(max_ramp, max(online_ramp));
    online_load = schedule.load(schedule.hb_on == 1);
    minimum_online_load = min(minimum_online_load, min(online_load));
    maximum_online_load = max(maximum_online_load, max(online_load));
    off_load_error = max(off_load_error, ...
        max(abs(schedule.load(schedule.hb_on == 0))));
    max_balance_residual = max(max_balance_residual, ...
        max(abs(schedule.balance_residual)));
    minimum_soc = min(minimum_soc, min(schedule.h2_soc));
    maximum_soc = max(maximum_soc, max(schedule.h2_soc));
end

metrics = array2table(metric_values, ...
    'VariableNames', cellstr(registry.Name));
feasibility.MaxRamp = max_ramp;
feasibility.MaxBalanceResidual = max_balance_residual;
feasibility.MinimumSOC = minimum_soc;
feasibility.MaximumSOC = maximum_soc;
feasibility.MinimumOnlineLoad = minimum_online_load;
feasibility.MaximumOnlineLoad = maximum_online_load;
feasibility.OffLoadError = off_load_error;
feasibility.Pass = max_ramp <= config.ramp_limit + 1e-12 && ...
    max_balance_residual <= 1e-10 && minimum_soc >= -1e-12 && ...
    maximum_soc <= 1 + 1e-12 && ...
    minimum_online_load >= config.load_bounds(1) - 1e-12 && ...
    maximum_online_load <= config.load_bounds(2) + 1e-12 && ...
    off_load_error <= 1e-12;
end

function forcing = generatedForcing(sample_count, schedule_index, repetition)
time = (0:(sample_count - 1))';
phase = mod(0.71 * schedule_index + 0.37 * repetition, 2 * pi);
daily = 0.50 + 0.30 * sin(2 * pi * time / 24 + phase);
weekly = 0.12 * sin(2 * pi * time / 168 + 0.5 * phase);
deterministic_noise = 0.06 * sin(2 * pi * time / 11 + 1.7 * phase);
forcing = clamp(daily + weekly + deterministic_noise, 0, 1);
end

function schedule = generateFeasibleSchedule(factor, forcing, config)
sample_count = numel(forcing);
time = (0:(sample_count - 1))';
day_index = floor(time / 24);
hour_index = mod(time, 24);

intraday_amplitude = 0.01 + 0.05 * factor(1);
interday_spread = 0.06 * factor(2);
ramp_intensity = factor(3);
switch_frequency = factor(4);
low_load_fraction = factor(5);
h2_stress = factor(6);

intraday = intraday_amplitude * sin(2 * pi * hour_index / 24);
interday_pattern = sin(2 * pi * (day_index + 0.5) / 14);
interday = interday_spread * interday_pattern;
ramp_amplitude = 0.005 + 0.035 * ramp_intensity;
ramp_component = ramp_amplitude * (-1) .^ time;
forcing_component = 0.02 * (forcing - 0.5);
desired_load = 0.66 + forcing_component + intraday + interday + ...
    ramp_component;

hb_on = buildHbOnState(sample_count, switch_frequency);
low_hours_per_day = round(6 * low_load_fraction);
day_count = ceil(sample_count / 24);
for day = 1:day_count
    day_rows = ((day - 1) * 24 + 1):min(day * 24, sample_count);
    online_rows = day_rows(hb_on(day_rows) == 1);
    selected_count = min(low_hours_per_day, numel(online_rows));
    if selected_count > 0
        desired_load(online_rows(1:selected_count)) = ...
            0.32 + 0.01 * ramp_intensity;
    end
end

load = zeros(sample_count, 1);
online_rows = find(hb_on == 1);
load(online_rows) = clamp(desired_load(online_rows), ...
    config.load_bounds(1), config.load_bounds(2));
load = enforceOnlineRamp(load, hb_on, config.ramp_limit, ...
    config.load_bounds);

[h2_soc, h2_production, h2_demand, spill, balance_residual] = ...
    simulateHydrogenBalance(load, forcing, h2_stress, config);
schedule.load = load;
schedule.hb_on = hb_on;
schedule.h2_soc = h2_soc;
schedule.h2_production = h2_production;
schedule.h2_demand = h2_demand;
schedule.spill = spill;
schedule.balance_residual = balance_residual;
end

function hb_on = buildHbOnState(sample_count, switch_frequency)
if switch_frequency < 1 / 3
    off_hours = 19:24;
elseif switch_frequency < 2 / 3
    off_hours = [5, 6, 13, 14, 21, 22];
else
    off_hours = [4, 8, 12, 16, 20, 24];
end
hb_on = ones(sample_count, 1);
for start_index = 1:24:sample_count
    day_rows = start_index:min(start_index + 23, sample_count);
    local_off = off_hours(off_hours <= numel(day_rows));
    hb_on(day_rows(local_off)) = 0;
end
end

function load = enforceOnlineRamp(load, hb_on, ramp_limit, load_bounds)
for time_index = 2:numel(load)
    if hb_on(time_index - 1) == 1 && hb_on(time_index) == 1
        load(time_index) = load(time_index - 1) + clamp(...
            load(time_index) - load(time_index - 1), ...
            -ramp_limit, ramp_limit);
        load(time_index) = clamp(load(time_index), ...
            load_bounds(1), load_bounds(2));
    end
end
end

function [soc, production, demand, spill, residual] = ...
        simulateHydrogenBalance(load, forcing, stress, config)
sample_count = numel(load);
capacity = config.h2_capacity_hours;
efficiency = config.h2_conversion_efficiency;
state = zeros(sample_count + 1, 1);
soc_target = 0.65 - 0.43 * stress;
state(1) = capacity * clamp(soc_target + 0.05, 0.05, 0.95);
production = zeros(sample_count, 1);
demand = load;
spill = zeros(sample_count, 1);
residual = zeros(sample_count, 1);

for time_index = 1:sample_count
    renewable_target = 0.20 + 1.05 * forcing(time_index) - 0.16 * stress;
    inventory_control = 0.28 * (soc_target * capacity - state(time_index));
    desired_production = clamp(renewable_target + inventory_control, ...
        0, config.ael_h2_max);
    minimum_production = max(...
        (demand(time_index) - state(time_index)) / efficiency, 0);
    production(time_index) = min(max(desired_production, ...
        minimum_production), config.ael_h2_max);

    raw_next = state(time_index) + efficiency * ...
        production(time_index) - demand(time_index);
    if raw_next > capacity
        spill(time_index) = raw_next - capacity;
        raw_next = capacity;
    end
    if raw_next < -1e-12
        error('test_chose_index:infeasible_h2_balance', ...
            'AEL production and stored H2 cannot satisfy HB demand.');
    end
    state(time_index + 1) = max(raw_next, 0);
    residual(time_index) = state(time_index + 1) - ...
        state(time_index) - efficiency * production(time_index) + ...
        demand(time_index) + spill(time_index);
end
soc = state / capacity;
end

function effects = evaluateFactorEffects(metrics, factors, repetition, ...
        registry, config, bootstrap_iterations)
delta = zeros(height(registry), 1);
cohen_d = zeros(height(registry), 1);
ci_low = zeros(height(registry), 1);
ci_high = zeros(height(registry), 1);
correct_direction = false(height(registry), 1);
replication_direction_rate = zeros(height(registry), 1);

for metric_index = 1:height(registry)
    feature = factors.(char(registry.TargetFeature(metric_index)));
    values = metrics.(char(registry.Name(metric_index)));
    direction = 2 * double(registry.LargerIsWorse(metric_index)) - 1;
    risk_values = direction * values;
    [low, high] = extremeGroups(feature, risk_values);
    delta(metric_index) = cliffsDelta(high, low);
    cohen_d(metric_index) = cohensD(high, low);
    [ci_low(metric_index), ci_high(metric_index)] = ...
        bootstrapCliffsDelta(high, low, bootstrap_iterations, ...
        config.random_seed + metric_index);
    correct_direction(metric_index) = median(high) > median(low);

    repetition_pass = false(max(repetition), 1);
    for repetition_index = 1:max(repetition)
        rows = repetition == repetition_index;
        [rep_low, rep_high] = extremeGroups(...
            feature(rows), risk_values(rows));
        repetition_pass(repetition_index) = ...
            median(rep_high) > median(rep_low);
    end
    replication_direction_rate(metric_index) = mean(repetition_pass);
end

pass = correct_direction & ...
    delta >= config.cliffs_delta_threshold & ...
    ci_low > config.effect_ci_lower_threshold;
effects = table(registry.Name, registry.Family, registry.TargetFeature, ...
    delta, cohen_d, ci_low, ci_high, correct_direction, ...
    replication_direction_rate, pass, 'VariableNames', ...
    {'Name', 'Family', 'TargetFeature', 'CliffsDelta', 'CohensD', ...
    'CILow', 'CIHigh', 'CorrectDirection', ...
    'ReplicationDirectionRate', 'Pass'});
end

function [low, high] = extremeGroups(feature, values)
lower_bound = prctile(feature, 25);
upper_bound = prctile(feature, 75);
low = values(feature <= lower_bound);
high = values(feature >= upper_bound);
end

function step = buildFeasibleEngineeringBenchmark(protocol)
config = protocol.Config;
registry = protocol.Registry;
[factors, repetition] = generateFactorMatrix(config.engineering_seed, ...
    1, config.engineering_schedule_count);
sample_count = config.engineering_days * 24;
schedule_count = height(factors);
load = zeros(sample_count, schedule_count);
h2_soc = zeros(sample_count + 1, schedule_count);
h2_production = zeros(sample_count, schedule_count);
h2_demand = zeros(sample_count, schedule_count);
hb_on = zeros(sample_count, schedule_count);
spill = zeros(sample_count, schedule_count);
balance_residual = zeros(sample_count, schedule_count);
metric_values = zeros(schedule_count, height(registry));

for schedule_index = 1:schedule_count
    forcing = generatedForcing(sample_count, schedule_index + 400, 1);
    factor = table2array(factors(schedule_index, :));
    schedule = generateFeasibleSchedule(factor, forcing, config);
    load(:, schedule_index) = schedule.load;
    h2_soc(:, schedule_index) = schedule.h2_soc;
    h2_production(:, schedule_index) = schedule.h2_production;
    h2_demand(:, schedule_index) = schedule.h2_demand;
    hb_on(:, schedule_index) = schedule.hb_on;
    spill(:, schedule_index) = schedule.spill;
    balance_residual(:, schedule_index) = schedule.balance_residual;
    metric_values(schedule_index, :) = metricVector(...
        schedule.load, schedule.h2_soc(2:end), schedule.hb_on, ...
        registry, config);
end

step.factors = factors;
step.repetition = repetition;
step.load = load;
step.h2_soc = h2_soc;
step.h2_production = h2_production;
step.h2_demand = h2_demand;
step.hb_on = hb_on;
step.h2_spill = spill;
step.balance_residual = balance_residual;
step.metrics = array2table(metric_values, ...
    'VariableNames', cellstr(registry.Name));
step.description = "Feasibility-aware engineering benchmark with " + ...
    "explicit hourly H2 balance; not an economic MILP solution";
online_load = load(hb_on == 1);
off_load = load(hb_on == 0);
online_ramps = onlineRampValues(load, hb_on, config.dt);
step.max_online_ramp = max(online_ramps);
step.complete = all(hb_on(:) == 0 | hb_on(:) == 1) && ...
    all(online_load >= config.load_bounds(1) - 1e-12) && ...
    all(online_load <= config.load_bounds(2) + 1e-12) && ...
    all(abs(off_load) <= 1e-12) && ...
    step.max_online_ramp <= config.ramp_limit + 1e-12 && ...
    all(h2_soc(:) >= -1e-12 & h2_soc(:) <= 1 + 1e-12) && ...
    all(h2_production(:) >= 0) && ...
    max(abs(balance_residual), [], 'all') <= 1e-10 && ...
    all(isfinite(metric_values), 'all');
end

function step = evaluateValidity(protocol, deterministic, random_benchmark)
registry = protocol.Registry;
config = protocol.Config;
effects = random_benchmark.effects;
mandatory_pass = false(height(registry), 1);
other_pass_rate = zeros(height(registry), 1);
monotonicity_rho = zeros(height(registry), 1);
conditional_direction_rate = zeros(height(registry), 1);
saturation_ratio = zeros(height(registry), 1);
saturated = false(height(registry), 1);
combined_audit = [deterministic.audit; deterministic.h2_security_audit];

for metric_index = 1:height(registry)
    mandatory_row = protocol.MandatoryDeterministicTests.Metric == ...
        registry.Name(metric_index);
    mandatory_test = ...
        protocol.MandatoryDeterministicTests.Test(mandatory_row);
    audit_rows = combined_audit.Metric == registry.Name(metric_index);
    metric_audit = combined_audit(audit_rows, :);
    required_row = metric_audit.Test == mandatory_test;
    mandatory_pass(metric_index) = ...
        any(required_row) && all(metric_audit.Pass(required_row));
    other_rows = ~required_row;
    if any(other_rows)
        other_pass_rate(metric_index) = ...
            mean(metric_audit.Pass(other_rows));
    else
        other_pass_rate(metric_index) = 1;
    end

    feature = random_benchmark.factors.(char(...
        registry.TargetFeature(metric_index)));
    values = random_benchmark.metrics.(char(registry.Name(metric_index)));
    direction = 2 * double(registry.LargerIsWorse(metric_index)) - 1;
    risk_values = direction * values;
    control_names = setdiff(string(...
        random_benchmark.factors.Properties.VariableNames)', ...
        registry.TargetFeature(metric_index), 'stable');
    controls = table2array(random_benchmark.factors(:, ...
        cellstr(control_names)));
    monotonicity_rho(metric_index) = partialSpearman(...
        feature, risk_values, controls);
    conditional_direction_rate(metric_index) = ...
        conditionalDirectionRate(feature, risk_values, controls);
    if ~isfinite(monotonicity_rho(metric_index))
        monotonicity_rho(metric_index) = 0;
    end
    saturation_ratio(metric_index) = binnedSaturationRatio(...
        feature, risk_values);
    saturated(metric_index) = saturation_ratio(metric_index) < ...
        config.saturation_ratio_threshold;
end

effect_pass = effects.Pass;
other_deterministic_pass = other_pass_rate >= ...
    config.deterministic_pass_rate;
monotonicity_pass = monotonicity_rho >= ...
    config.monotonicity_threshold;
validity_pass = mandatory_pass & other_deterministic_pass & ...
    effect_pass & monotonicity_pass;

monotonicity_method = repmat("partial_Spearman", height(registry), 1);
step.validity = table(registry.Name, registry.Family, ...
    registry.UpperDimension, mandatory_pass, other_pass_rate, ...
    other_deterministic_pass, effects.CliffsDelta, effects.CohensD, ...
    effects.CILow, effect_pass, monotonicity_rho, ...
    monotonicity_method, conditional_direction_rate, ...
    monotonicity_pass, saturation_ratio, saturated, validity_pass, ...
    'VariableNames', {'Name', 'Family', 'UpperDimension', ...
    'MandatoryDeterministicPass', 'OtherApplicablePassRate', ...
    'OtherDeterministicPass', 'CliffsDelta', 'CohensD', 'CILow', ...
    'EffectPass', 'MonotonicityRho', 'MonotonicityMethod', ...
    'ConditionalDirectionRate', 'MonotonicityPass', ...
    'SaturationRatio', 'SaturatedAtUpperQuintile', 'ValidityPass'});
step.note = "Saturation is reported, not used as a hidden deletion rule.";
step.complete = all(isfinite(other_pass_rate)) && ...
    all(isfinite(monotonicity_rho)) && ...
    all(isfinite(conditional_direction_rate)) && ...
    all(isfinite(saturation_ratio));
end

function rho = partialSpearman(target, values, controls)
target_rank = tiedrank(target(:));
value_rank = tiedrank(values(:));
control_rank = zeros(size(controls));
for control_index = 1:size(controls, 2)
    control_rank(:, control_index) = tiedrank(controls(:, control_index));
end
design = [ones(numel(target_rank), 1), control_rank];
target_residual = target_rank - design * (design \ target_rank);
value_residual = value_rank - design * (design \ value_rank);
rho = corr(target_residual, value_residual, 'Rows', 'complete');
if ~isfinite(rho)
    rho = 0;
end
end

function rate = conditionalDirectionRate(target, values, controls)
[~, ~, group] = unique(controls, 'rows');
group_count = max(group);
passes = false(group_count, 1);
for group_index = 1:group_count
    rows = group == group_index;
    group_target = target(rows);
    group_values = values(rows);
    low_value = median(group_values(group_target == min(group_target)));
    high_value = median(group_values(group_target == max(group_target)));
    passes(group_index) = high_value > low_value;
end
rate = mean(passes);
end

function saturation_ratio = binnedSaturationRatio(feature, values)
edges = prctile(feature, 0:20:100);
edges(1) = -inf;
edges(end) = inf;
for edge_index = 2:(numel(edges) - 1)
    if edges(edge_index) <= edges(edge_index - 1)
        edges(edge_index) = edges(edge_index - 1) + eps(...
            max(abs(edges(edge_index - 1)), 1));
    end
end
bins = discretize(feature, edges);
bin_median = zeros(5, 1);
for bin_index = 1:5
    bin_median(bin_index) = median(values(bins == bin_index));
end
if all(abs(bin_median - bin_median(1)) <= 1e-12)
    saturation_ratio = 0;
    return
end
full_change = abs(bin_median(end) - bin_median(1));
if full_change <= 1e-12
    saturation_ratio = 0;
else
    saturation_ratio = abs(bin_median(end) - bin_median(end - 1)) / ...
        full_change;
end
saturation_ratio = max(saturation_ratio, 0);
end

function step = screenRedundancyAndIncrementalInformation(...
        protocol, deterministic, random_benchmark, engineering)
registry = protocol.Registry;
config = protocol.Config;
values = table2array(engineering.metrics(:, cellstr(registry.Name)));
pearson = corr(values, 'Type', 'Pearson', 'Rows', 'pairwise');
spearman = corr(values, 'Type', 'Spearman', 'Rows', 'pairwise');
constant_metric = std(values, 0, 1)' <= eps;
pearson(~isfinite(pearson)) = 0;
spearman(~isfinite(spearman)) = 0;
nmi = normalizedMutualInformationMatrix(values, 6);
pearson(1:(height(registry) + 1):end) = 1;
spearman(1:(height(registry) + 1):end) = 1;
nmi(1:(height(registry) + 1):end) = 1;
[cluster_id, hierarchical_tree] = hierarchicalCorrelationClusters(spearman, ...
    config.spearman_redundancy);

first_name = strings(0, 1);
second_name = strings(0, 1);
family = strings(0, 1);
abs_pearson = zeros(0, 1);
abs_spearman = zeros(0, 1);
pair_nmi = zeros(0, 1);
statistically_redundant = false(0, 1);
functionally_redundant = false(0, 1);
mathematically_redundant = false(0, 1);
drop_candidate = strings(0, 1);

expected_signature = expectedSignatureMatrix(protocol);
observed_signature = deterministic.functional_signature;
for first_index = 1:height(registry)
    for second_index = (first_index + 1):height(registry)
        if registry.Family(first_index) ~= registry.Family(second_index)
            continue
        end
        statistical = abs(pearson(first_index, second_index)) >= ...
            config.pearson_redundancy && ...
            abs(spearman(first_index, second_index)) >= ...
            config.spearman_redundancy && ...
            nmi(first_index, second_index) >= config.nmi_redundancy;
        functional = isequal(expected_signature(:, first_index), ...
            expected_signature(:, second_index)) && ...
            isequal(observed_signature(:, first_index), ...
            observed_signature(:, second_index));
        mathematical = isMathematicalPair(protocol.MathematicalPairs, ...
            registry.Name(first_index), registry.Name(second_index));
        if mathematical || (statistical && functional)
            first_name(end + 1, 1) = registry.Name(first_index); %#ok<AGROW>
            second_name(end + 1, 1) = registry.Name(second_index); %#ok<AGROW>
            family(end + 1, 1) = registry.Family(first_index); %#ok<AGROW>
            abs_pearson(end + 1, 1) = ...
                abs(pearson(first_index, second_index)); %#ok<AGROW>
            abs_spearman(end + 1, 1) = ...
                abs(spearman(first_index, second_index)); %#ok<AGROW>
            pair_nmi(end + 1, 1) = nmi(first_index, second_index); %#ok<AGROW>
            statistically_redundant(end + 1, 1) = statistical; %#ok<AGROW>
            functionally_redundant(end + 1, 1) = functional; %#ok<AGROW>
            mathematically_redundant(end + 1, 1) = mathematical; %#ok<AGROW>
            can_compete = registry.CoreEligible(first_index) && ...
                registry.CoreEligible(second_index) && ...
                registry.FunctionalPosition(first_index) == ...
                registry.FunctionalPosition(second_index);
            if can_compete
                drop_candidate(end + 1, 1) = lowerPreferenceMetric(...
                    registry, first_index, second_index); %#ok<AGROW>
            else
                drop_candidate(end + 1, 1) = "none"; %#ok<AGROW>
            end
        end
    end
end

flagged_pairs = table(first_name, second_name, family, abs_pearson, ...
    abs_spearman, pair_nmi, mathematically_redundant, ...
    statistically_redundant, functionally_redundant, drop_candidate, ...
    'VariableNames', {'FirstMetric', 'SecondMetric', 'Family', ...
    'AbsPearson', 'AbsSpearman', 'NormalizedMI', ...
    'MathematicallyRedundant', 'StatisticallyRedundant', ...
    'FunctionallyRedundant', 'DropCandidate'});

incremental_information = evaluateIncrementalInformation(...
    registry, random_benchmark.metrics, random_benchmark.factors);
functional_unique = true(height(registry), 1);
for metric_index = 1:height(registry)
    same_family = find(registry.Family == registry.Family(metric_index) & ...
        registry.FunctionalPosition == ...
        registry.FunctionalPosition(metric_index));
    same_family(same_family == metric_index) = [];
    for other_index = same_family'
        if isequal(expected_signature(:, metric_index), ...
                expected_signature(:, other_index)) && ...
                isequal(observed_signature(:, metric_index), ...
                observed_signature(:, other_index))
            functional_unique(metric_index) = false;
            break
        end
    end
end
incremental_information.FunctionallyUnique = functional_unique;

step.mathematical_pairs = protocol.MathematicalPairs;
step.pearson = pearson;
step.spearman = spearman;
step.normalized_mutual_information = nmi;
step.hierarchical_tree = hierarchical_tree;
step.constant_metric = table(registry.Name, constant_metric, ...
    'VariableNames', {'Name', 'IsConstantInEngineeringBenchmark'});
step.cluster_id = cluster_id;
step.flagged_pairs = flagged_pairs;
step.incremental_information = incremental_information;
step.rule = protocol.RedundancyRule;
step.complete = all(isfinite(pearson), 'all') && ...
    all(isfinite(spearman), 'all') && all(isfinite(nmi), 'all') && ...
    all(incremental_information.IncrementalR2 >= 0);
end

function signature = expectedSignatureMatrix(protocol)
registry = protocol.Registry;
tests = protocol.DeterministicTests;
expected = protocol.ExpectedResponse;
signature = 9 * ones(height(tests), height(registry));
for test_index = 1:height(tests)
    for metric_index = 1:height(registry)
        row = expected.Test == tests.Name(test_index) & ...
            expected.Metric == registry.Name(metric_index);
        response = expected.Expected(row);
        switch response
            case {"increase", "positive"}
                signature(test_index, metric_index) = 1;
            case "decrease"
                signature(test_index, metric_index) = -1;
            case {"invariant", "zero"}
                signature(test_index, metric_index) = 0;
            otherwise
                signature(test_index, metric_index) = 9;
        end
    end
end
end

function is_pair = isMathematicalPair(pairs, first_name, second_name)
if isempty(pairs)
    is_pair = false;
    return
end
is_pair = any((pairs.FirstMetric == first_name & ...
    pairs.SecondMetric == second_name) | ...
    (pairs.FirstMetric == second_name & pairs.SecondMetric == first_name));
end

function matrix = normalizedMutualInformationMatrix(values, bin_count)
metric_count = size(values, 2);
matrix = eye(metric_count);
discrete = zeros(size(values));
entropy = zeros(metric_count, 1);
for metric_index = 1:metric_count
    discrete(:, metric_index) = quantileBins(values(:, metric_index), ...
        bin_count);
    entropy(metric_index) = discreteEntropy(discrete(:, metric_index));
end
for first_index = 1:metric_count
    for second_index = (first_index + 1):metric_count
        mutual_information = discreteMutualInformation(...
            discrete(:, first_index), discrete(:, second_index));
        denominator = sqrt(entropy(first_index) * entropy(second_index));
        if denominator <= eps
            value = double(all(discrete(:, first_index) == ...
                discrete(:, second_index)));
        else
            value = mutual_information / denominator;
        end
        matrix(first_index, second_index) = value;
        matrix(second_index, first_index) = value;
    end
end
matrix = clamp(matrix, 0, 1);
end

function bins = quantileBins(values, bin_count)
edges = unique(prctile(values, linspace(0, 100, bin_count + 1)));
if numel(edges) < 2
    bins = ones(size(values));
    return
end
edges(1) = -inf;
edges(end) = inf;
bins = discretize(values, edges);
end

function entropy_value = discreteEntropy(values)
labels = unique(values);
probability = zeros(numel(labels), 1);
for label_index = 1:numel(labels)
    probability(label_index) = mean(values == labels(label_index));
end
probability = probability(probability > 0);
entropy_value = -sum(probability .* log(probability));
end

function value = discreteMutualInformation(first, second)
first_labels = unique(first);
second_labels = unique(second);
value = 0;
for first_index = 1:numel(first_labels)
    first_probability = mean(first == first_labels(first_index));
    for second_index = 1:numel(second_labels)
        second_probability = mean(second == second_labels(second_index));
        joint_probability = mean(first == first_labels(first_index) & ...
            second == second_labels(second_index));
        if joint_probability > 0
            value = value + joint_probability * log(joint_probability / ...
                (first_probability * second_probability));
        end
    end
end
end

function [cluster_id, tree] = hierarchicalCorrelationClusters(...
        spearman, threshold)
distance = 1 - abs(spearman);
distance = max((distance + distance') / 2, 0);
distance(1:(size(distance, 1) + 1):end) = 0;
condensed_distance = squareform(distance, 'tovector');
tree = linkage(condensed_distance, 'average');
cluster_id = cluster(tree, 'cutoff', 1 - threshold, ...
    'criterion', 'distance');
end

function result = evaluateIncrementalInformation(registry, metrics, factors)
incremental_r2 = zeros(height(registry), 1);
baseline_r2 = zeros(height(registry), 1);
augmented_r2 = zeros(height(registry), 1);
competitor = strings(height(registry), 1);
fold = mod((1:height(metrics))' - 1, 5) + 1;

for metric_index = 1:height(registry)
    target = factors.(char(registry.TargetFeature(metric_index)));
    same_family = find(registry.Family == registry.Family(metric_index) & ...
        registry.FunctionalPosition == ...
        registry.FunctionalPosition(metric_index) & ...
        registry.CoreEligible == registry.CoreEligible(metric_index));
    same_family(same_family == metric_index) = [];
    candidate = metrics.(char(registry.Name(metric_index)));
    if isempty(same_family)
        baseline_r2(metric_index) = 0;
        augmented_r2(metric_index) = crossValidatedR2(...
            candidate, target, fold);
        incremental_r2(metric_index) = max(augmented_r2(metric_index), 0);
        competitor(metric_index) = "none";
        continue
    end

    competing_r2 = zeros(numel(same_family), 1);
    for competitor_index = 1:numel(same_family)
        competing_values = metrics.(char(...
            registry.Name(same_family(competitor_index))));
        competing_r2(competitor_index) = crossValidatedR2(...
            competing_values, target, fold);
    end
    [baseline_r2(metric_index), best_index] = max(competing_r2);
    best_metric_index = same_family(best_index);
    competitor(metric_index) = registry.Name(best_metric_index);
    competing_values = metrics.(char(registry.Name(best_metric_index)));
    augmented_r2(metric_index) = crossValidatedR2(...
        [competing_values, candidate], target, fold);
    incremental_r2(metric_index) = max(...
        augmented_r2(metric_index) - baseline_r2(metric_index), 0);
end

result = table(registry.Name, registry.Family, competitor, baseline_r2, ...
    augmented_r2, incremental_r2, 'VariableNames', ...
    {'Name', 'Family', 'BestCompetingMetric', 'BaselineR2', ...
    'AugmentedR2', 'IncrementalR2'});
end

function r2 = crossValidatedR2(predictors, target, fold)
prediction = zeros(size(target));
for fold_index = 1:max(fold)
    training = fold ~= fold_index;
    testing = fold == fold_index;
    training_matrix = [ones(sum(training), 1), predictors(training, :)];
    coefficients = training_matrix \ target(training);
    testing_matrix = [ones(sum(testing), 1), predictors(testing, :)];
    prediction(testing) = testing_matrix * coefficients;
end
denominator = sum((target - mean(target)) .^ 2);
if denominator <= eps
    r2 = 0;
else
    r2 = 1 - sum((target - prediction) .^ 2) / denominator;
end
r2 = max(r2, 0);
end

function name = lowerPreferenceMetric(registry, first_index, second_index)
if registry.CorePreference(first_index) < registry.CorePreference(second_index)
    name = registry.Name(first_index);
    return
elseif registry.CorePreference(second_index) < registry.CorePreference(first_index)
    name = registry.Name(second_index);
    return
end
first_score = engineeringScore(registry(first_index, :));
second_score = engineeringScore(registry(second_index, :));
if first_score < second_score
    name = registry.Name(first_index);
elseif second_score < first_score
    name = registry.Name(second_index);
else
    ordered = sort([registry.Name(first_index); registry.Name(second_index)]);
    name = ordered(2);
end
end

function score = engineeringScore(registry_row)
score = registry_row.InterpretabilityScore + ...
    registry_row.ActionabilityScore + ...
    registry_row.ReproducibilityScore + ...
    registry_row.OptimizationCompatibilityScore;
end

function step = evaluateParameterRobustness(protocol, engineering)
registry = protocol.Registry;
config = protocol.Config;
baseline = table2array(engineering.metrics(:, cellstr(registry.Name)));
[results, summary, hard_complete] = evaluateRobustnessGrid(...
    protocol.RobustnessGrid, engineering, baseline, registry, config);
[sensitivity_results, sensitivity_summary, sensitivity_complete] = ...
    evaluateRobustnessGrid(protocol.SensitivityGrid, engineering, ...
    baseline, registry, config);

step.results = results;
step.summary = summary;
step.sensitivity_results = sensitivity_results;
step.sensitivity_summary = sensitivity_summary;
step.grid = protocol.RobustnessGrid;
step.sensitivity_grid = protocol.SensitivityGrid;
step.applicability = protocol.RobustnessApplicability;
step.applicability_rule = "V4 hard Kendall is evaluated only for each " + ...
    "metric's frozen, definition-matched parameters. Sampling scale is " + ...
    "fixed at one hour and remains diagnostic only.";
step.complete = hard_complete && sensitivity_complete;
end

function [results, summary, complete] = evaluateRobustnessGrid(...
        grid, engineering, baseline, registry, config)
parameter = strings(0, 1);
parameter_value = zeros(0, 1);
metric_name = strings(0, 1);
tau = zeros(0, 1);
baseline_tie_rate = zeros(0, 1);
trial_tie_rate = zeros(0, 1);
pairwise_agreement = zeros(0, 1);

for grid_index = 1:height(grid)
    variant_name = grid.Parameter(grid_index);
    values = parseNumberList(grid.Values(grid_index));
    affected_metrics = split(grid.Metrics(grid_index), ',');
    for value_index = 1:numel(values)
        variant_value = values(value_index);
        [trial_load, trial_h2, trial_hb_on, trial_config] = applyGridVariant(...
            engineering, config, variant_name, variant_value);
        trial = metricMatrix(trial_load, trial_h2, trial_hb_on, ...
            registry, trial_config);

        for affected_index = 1:numel(affected_metrics)
            name = affected_metrics(affected_index);
            metric_index = find(registry.Name == name, 1);
            direction = 2 * double(...
                registry.LargerIsWorse(metric_index)) - 1;
            [metric_tau, baseline_ties, trial_ties, agreement] = ...
                rankAgreement(...
                direction * baseline(:, metric_index), ...
                direction * trial(:, metric_index));
            parameter(end + 1, 1) = variant_name; %#ok<AGROW>
            parameter_value(end + 1, 1) = variant_value; %#ok<AGROW>
            metric_name(end + 1, 1) = name; %#ok<AGROW>
            tau(end + 1, 1) = metric_tau; %#ok<AGROW>
            baseline_tie_rate(end + 1, 1) = baseline_ties; %#ok<AGROW>
            trial_tie_rate(end + 1, 1) = trial_ties; %#ok<AGROW>
            pairwise_agreement(end + 1, 1) = agreement; %#ok<AGROW>
        end
    end
end

pass = tau >= config.kendall_threshold;
results = table(parameter, parameter_value, metric_name, tau, ...
    baseline_tie_rate, trial_tie_rate, pairwise_agreement, pass, ...
    'VariableNames', ...
    {'Parameter', 'ParameterValue', 'Metric', 'KendallTau', ...
    'BaselineTieRate', 'TrialTieRate', 'PairwiseAgreement', 'Pass'});

worst_tau = zeros(height(registry), 1);
maximum_tie_rate_change = zeros(height(registry), 1);
minimum_pairwise_agreement = zeros(height(registry), 1);
robust = false(height(registry), 1);
applicable_setting_count = zeros(height(registry), 1);
for metric_index = 1:height(registry)
    rows = results.Metric == registry.Name(metric_index);
    applicable_setting_count(metric_index) = sum(rows);
    if ~any(rows)
        worst_tau(metric_index) = 1;
        maximum_tie_rate_change(metric_index) = 0;
        minimum_pairwise_agreement(metric_index) = 1;
        robust(metric_index) = true;
        continue
    end
    worst_tau(metric_index) = min(results.KendallTau(rows));
    maximum_tie_rate_change(metric_index) = max(abs(...
        results.TrialTieRate(rows) - results.BaselineTieRate(rows)));
    minimum_pairwise_agreement(metric_index) = ...
        min(results.PairwiseAgreement(rows));
    robust(metric_index) = ...
        worst_tau(metric_index) >= config.kendall_threshold;
end

summary = table(registry.Name, worst_tau, maximum_tie_rate_change, ...
    minimum_pairwise_agreement, applicable_setting_count, robust, ...
    'VariableNames', ...
    {'Name', 'WorstKendallTau', 'MaximumTieRateChange', ...
    'MinimumPairwiseAgreement', 'ApplicableSettingCount', 'Robust'});
complete = all(isfinite(tau)) && all(tau >= -1 & tau <= 1) && ...
    all(baseline_tie_rate >= 0 & baseline_tie_rate <= 1) && ...
    all(trial_tie_rate >= 0 & trial_tie_rate <= 1) && ...
    all(pairwise_agreement >= 0 & pairwise_agreement <= 1);
end

function [trial_load, trial_h2, trial_hb_on, trial_config] = ...
        applyGridVariant(...
        engineering, config, variant_name, variant_value)
trial_config = config;
trial_load = engineering.load;
trial_h2 = engineering.h2_soc(2:end, :);
trial_hb_on = engineering.hb_on;
switch variant_name
    case "sampling_hours"
        [trial_load, trial_h2, trial_hb_on] = aggregateSamples(...
            trial_load, trial_h2, trial_hb_on, variant_value);
        trial_config.dt = variant_value;
    case "load_measurement_noise"
        pattern = deterministicNoisePattern(size(trial_load));
        online = trial_hb_on == 1;
        trial_load(online) = clamp(...
            trial_load(online) + variant_value * pattern(online), ...
            config.load_bounds(1), config.load_bounds(2));
        trial_load(~online) = 0;
    case "h2_measurement_noise"
        pattern = deterministicNoisePattern(size(trial_h2));
        trial_h2 = clamp(trial_h2 + variant_value * pattern, 0, 1);
    otherwise
        trial_config.(char(variant_name)) = variant_value;
end
end

function pattern = deterministicNoisePattern(matrix_size)
[time_index, schedule_index] = ndgrid(...
    (1:matrix_size(1))', 1:matrix_size(2));
pattern = sin(2 * pi * time_index / 17 + ...
    0.37 * schedule_index) + 0.5 * sin(...
    2 * pi * time_index / 7 + 0.19 * schedule_index);
pattern = pattern / max(abs(pattern), [], 'all');
end

function values = parseNumberList(text_value)
parts = split(text_value, ',');
values = str2double(parts)';
end

function step = buildReferenceRanges(protocol, metrics)
registry = protocol.Registry;
values = table2array(metrics(:, cellstr(registry.Name)));
p25 = prctile(values, 25, 1)';
p50 = prctile(values, 50, 1)';
p75 = prctile(values, 75, 1)';
source_class = repmat("C", height(registry), 1);
reference_text = repmat(...
    "Engineering benchmark interval; not a universal safety standard", ...
    height(registry), 1);

dcv_rows = startsWith(registry.Name, "dcv_");
source_class(dcv_rows) = "B+C";
reference_text(dcv_rows) = ...
    "Zhou scenario DCV plus current engineering benchmark interval";
ramp_row = registry.Name == "ramp_max";
source_class(ramp_row) = "A+C";
reference_text(ramp_row) = ...
    "Frozen physical HB ramp limit plus empirical interval";
h2_row = registry.Name == "h2_risk_hours";
source_class(h2_row) = "A+C";
reference_text(h2_row) = ...
    "Operational objective is zero hours below frozen reserve line";
unresolved = registry.Name == "daily_output_cv" | ...
    registry.Name == "switch_count" | registry.Name == "low_load_ratio";
source_class(unresolved) = "C+D";
reference_text(unresolved) = ...
    "No universal literature limit; compare across frozen scenarios";

is_universal_standard = false(height(registry), 1);
step.reference_ranges = table(registry.Name, registry.Family, ...
    source_class, p25, p50, p75, reference_text, ...
    is_universal_standard, 'VariableNames', {'Name', 'Family', ...
    'SourceClass', 'P25', 'P50', 'P75', 'ReferenceText', ...
    'IsUniversalStandard'});
step.complete = all(isfinite([p25; p50; p75])) && ...
    all(p25 <= p50 & p50 <= p75) && ~any(is_universal_standard);
end

function step = mechanicallyLockCoreMetrics(protocol, deterministic, ...
        random_benchmark, engineering, validity, redundancy, ...
        robustness, reference_ranges)
if ~verifyProtocolSeal(protocol)
    error('test_chose_index:protocol_changed', ...
        'The frozen protocol changed after data generation.');
end
registry = protocol.Registry;
config = protocol.Config;
selection = registry(:, {'Name', 'Family', 'UpperDimension', 'Role', ...
    'FunctionalPosition', 'CoreEligible', 'CorePreference', 'TargetFeature', ...
    'InterpretabilityScore', 'ActionabilityScore', ...
    'ReproducibilityScore', 'OptimizationCompatibilityScore', ...
    'EngineeringAction'});
selection.ValidityPass = validity.validity.ValidityPass;
selection.MandatoryDeterministicPass = ...
    validity.validity.MandatoryDeterministicPass;
selection.OtherApplicablePassRate = ...
    validity.validity.OtherApplicablePassRate;
selection.OtherDeterministicPass = ...
    validity.validity.OtherDeterministicPass;
selection.EffectPass = validity.validity.EffectPass;
selection.MonotonicityPass = validity.validity.MonotonicityPass;
selection.CliffsDelta = random_benchmark.effects.CliffsDelta;
selection.CohenD = random_benchmark.effects.CohensD;
selection.EffectCILow = random_benchmark.effects.CILow;
selection.MonotonicityRho = validity.validity.MonotonicityRho;
selection.Robust = robustness.summary.Robust;
selection.WorstKendallTau = robustness.summary.WorstKendallTau;
selection.IncrementalR2 = ...
    redundancy.incremental_information.IncrementalR2;
selection.FunctionallyUnique = ...
    redundancy.incremental_information.FunctionallyUnique;
selection.RedundantLowerPreference = false(height(selection), 1);
selection.HasRedundancyPartner = false(height(selection), 1);
if ~isempty(redundancy.flagged_pairs)
    selection.RedundantLowerPreference = ismember(selection.Name, ...
        redundancy.flagged_pairs.DropCandidate);
    paired_names = unique([redundancy.flagged_pairs.FirstMetric; ...
        redundancy.flagged_pairs.SecondMetric]);
    selection.HasRedundancyPartner = ismember(selection.Name, paired_names);
end
selection.RedundancyPass = ~selection.RedundantLowerPreference;
selection.RedundancyRepresentative = ...
    selection.HasRedundancyPartner & selection.RedundancyPass;
selection.IncrementalInformationPass = selection.FunctionallyUnique | ...
    selection.IncrementalR2 >= config.incremental_r2_threshold | ...
    selection.RedundancyRepresentative;
selection.InterpretabilityPass = selection.InterpretabilityScore >= ...
    config.minimum_interpretability;
selection.ActionabilityPass = selection.ActionabilityScore >= ...
    config.minimum_actionability;
selection.ReproducibilityPass = selection.ReproducibilityScore >= ...
    config.minimum_reproducibility;
selection.OptimizationCompatibilityPass = ...
    selection.OptimizationCompatibilityScore >= ...
    config.minimum_optimization_compatibility;
selection.EngineeringRulePass = selection.InterpretabilityPass & ...
    selection.ActionabilityPass & selection.ReproducibilityPass & ...
    selection.OptimizationCompatibilityPass;
selection.EngineeringScore = ...
    selection.InterpretabilityScore + selection.ActionabilityScore + ...
    selection.ReproducibilityScore + ...
    selection.OptimizationCompatibilityScore;
selection.FunctionalCoverage = functionalCoverage(...
    deterministic.functional_signature);
prerequisites_complete = deterministic.complete && ...
    random_benchmark.complete && engineering.complete && ...
    validity.complete && redundancy.complete && robustness.complete && ...
    reference_ranges.complete;
selection.Eligible = prerequisites_complete & ...
    selection.CoreEligible & ...
    selection.ValidityPass & selection.Robust & ...
    selection.EngineeringRulePass & selection.RedundancyPass & ...
    selection.IncrementalInformationPass;
selection.Decision = repmat("drop", height(selection), 1);
selection.Reason = strings(height(selection), 1);
for metric_index = 1:height(selection)
    selection.Reason(metric_index) = failedGateReason(...
        selection, metric_index, prerequisites_complete);
end

families = unique(selection.Family, 'stable');
for family_index = 1:numel(families)
    rows = find(selection.Family == families(family_index) & ...
        selection.Eligible);
    if isempty(rows)
        continue
    end
    selected_index = rows(1);
    for row_index = 2:numel(rows)
        if isBetterCandidate(rows(row_index), selected_index, selection)
            selected_index = rows(row_index);
        end
    end
    selection.Decision(selected_index) = "nominee";
    selection.Reason(selected_index) = ...
        "Selected by the frozen lexicographic rule";
end

nominees = selection(selection.Decision == "nominee", :);
required_dimensions = protocol.SelectionRule.RequiredUpperDimensions;
upper_dimension_coverage_pass = all(ismember(...
    required_dimensions, unique(nominees.UpperDimension)));
if height(nominees) < protocol.SelectionRule.MinimumCoreCount || ...
        ~upper_dimension_coverage_pass
    selection.Decision(selection.Decision == "nominee") = "provisional";
    selection.Reason(selection.Decision == "provisional") = ...
        "Passed family rule, but upper-dimension stop rule was not met";
    freeze_status = "insufficient_evidence_no_confirmatory_lock";
else
    selection.Decision(selection.Decision == "nominee") = "core";
    freeze_status = "locked_pending_independent_2025_validation";
end
core = selection(selection.Decision == "core", :);

step.selection = selection;
step.freeze_status = freeze_status;
step.protocol_seal_verified = true;
step.mechanical_rule_executed = true;
step.selection_uses_holdout = false;
step.selection_input_steps = "04-10";
step.prerequisites_complete = prerequisites_complete;
step.tie_rule = protocol.TieRule;
step.stop_rule = protocol.SelectionRule.StopRule;
step.upper_dimension_coverage_pass = upper_dimension_coverage_pass;
step.complete = height(core) <= protocol.SelectionRule.MaximumCoreCount && ...
    numel(unique(core.Family)) == height(core) && ...
    (isempty(core) || numel(unique(core.UpperDimension)) == ...
    numel(required_dimensions));
end

function reason = failedGateReason(selection, metric_index, prerequisites)
failed = strings(0, 1);
if ~prerequisites
    failed(end + 1, 1) = "prerequisite";
end
gate_names = ["mandatory_deterministic"; "other_deterministic"; ...
    "Cliffs_delta"; "Spearman"; "Kendall"; "redundancy"; ...
    "incremental_information"; "engineering"; "core_functional_position"];
gate_values = [selection.MandatoryDeterministicPass(metric_index); ...
    selection.OtherDeterministicPass(metric_index); ...
    selection.EffectPass(metric_index); ...
    selection.MonotonicityPass(metric_index); ...
    selection.Robust(metric_index); ...
    selection.RedundancyPass(metric_index); ...
    selection.IncrementalInformationPass(metric_index); ...
    selection.EngineeringRulePass(metric_index); ...
    selection.CoreEligible(metric_index)];
failed = [failed; gate_names(~gate_values)];
if isempty(failed)
    reason = "All preregistered gates passed";
else
    reason = "Failed: " + strjoin(failed, ', ');
end
end

function coverage = functionalCoverage(signature)
coverage = sum(signature ~= 0, 1)';
end

function better = isBetterCandidate(candidate, current, selection)
candidate_values = [selection.CorePreference(candidate), ...
    selection.FunctionalCoverage(candidate), ...
    selection.IncrementalR2(candidate), ...
    selection.WorstKendallTau(candidate), ...
    selection.EffectCILow(candidate), ...
    selection.EngineeringScore(candidate)];
current_values = [selection.CorePreference(current), ...
    selection.FunctionalCoverage(current), ...
    selection.IncrementalR2(current), ...
    selection.WorstKendallTau(current), ...
    selection.EffectCILow(current), ...
    selection.EngineeringScore(current)];
better = false;
for value_index = 1:numel(candidate_values)
    if candidate_values(value_index) > current_values(value_index) + 1e-12
        better = true;
        return
    elseif candidate_values(value_index) < current_values(value_index) - 1e-12
        return
    end
end
better = selection.Name(candidate) < selection.Name(current);
end

function step = validateOnIndependent2025Data(protocol, locked)
if ~verifyProtocolSeal(protocol)
    error('test_chose_index:protocol_changed_before_holdout', ...
        'The protocol changed before independent validation.');
end
core = locked.selection(locked.selection.Decision == "core", :);
selected_names = sort(core.Name);
selection_hash_before = vectorChecksum(selected_names);
step.used_for_selection = false;
step.data_year = protocol.HoldoutRule.Year;
step.selection_hash_before = selection_hash_before;
step.sample_count = 0;
step.feasibility_pass = false;
step.effects = table();
step.data_available = false;
step.data_note = "2025 data not accessed before the pre-holdout gate passes";
step.holdout_authorized = false;

if locked.freeze_status ~= "locked_pending_independent_2025_validation"
    step.status = "skipped_preholdout_gate_not_satisfied";
    step.selection_hash_after = vectorChecksum(sort(core.Name));
    step.complete = step.selection_hash_before == step.selection_hash_after;
    return
end

unlock_name = protocol.HoldoutRule.UnlockEnvironment;
step.holdout_authorized = strcmpi(...
    string(getenv(char(unlock_name))), "YES");
if ~step.holdout_authorized
    step.status = "ready_but_2025_holdout_manually_locked";
    step.data_note = "V4 development gate passed; set " + ...
        unlock_name + "=YES only for the single confirmatory run";
    step.selection_hash_after = vectorChecksum(sort(core.Name));
    step.complete = step.selection_hash_before == step.selection_hash_after;
    return
end

[forcing, data_available, data_note] = load2025RenewableForcing();
step.data_available = data_available;
step.data_note = data_note;
if ~data_available
    step.status = "pending_missing_2025_renewable_data";
    step.selection_hash_after = vectorChecksum(sort(core.Name));
    step.complete = step.selection_hash_before == step.selection_hash_after;
    return
end

config = protocol.Config;
[factors, repetition] = generateFactorMatrix(config.holdout_seed, 1, ...
    config.holdout_schedule_count);
forcing_bank = buildHoldoutForcingBank(forcing, ...
    config.holdout_days_per_schedule * 24, height(factors));
[metrics, feasibility] = evaluateFactorSchedules(...
    factors, repetition, forcing_bank, protocol);
effects = evaluateFactorEffects(metrics, factors, repetition, ...
    protocol.Registry, config, round(config.bootstrap_iterations / 2));
core_effects = effects(ismember(effects.Name, core.Name), :);

step.sample_count = height(factors);
step.feasibility_pass = feasibility.Pass;
step.effects = core_effects;
step.feasibility = feasibility;
step.selection_hash_after = vectorChecksum(sort(core.Name));
if feasibility.Pass && all(core_effects.Pass)
    step.status = "independently_confirmed_on_2025_renewable_driven_proxy";
else
    step.status = "locked_set_not_fully_confirmed_on_2025_proxy";
end
step.complete = step.selection_hash_before == step.selection_hash_after && ...
    feasibility.Pass;
end

function [forcing, available, note] = load2025RenewableForcing()
test_directory = fileparts(mfilename('fullpath'));
project_directory = fileparts(test_directory);
wind_file = fullfile(project_directory, 'data', 'renewables_ninja', ...
    '2025PW.csv');
solar_file = fullfile(project_directory, 'data', 'renewables_ninja', ...
    '2025PV.csv');
available = isfile(wind_file) && isfile(solar_file);
if ~available
    forcing = [];
    note = "2025PW.csv or 2025PV.csv is unavailable";
    return
end

wind = readRenewableElectricity(wind_file);
solar = readRenewableElectricity(solar_file);
sample_count = min(numel(wind), numel(solar));
combined = 0.5 * wind(1:sample_count) + 0.5 * solar(1:sample_count);
lower = prctile(combined, 5);
upper = prctile(combined, 95);
forcing = clamp((combined - lower) / max(upper - lower, eps), 0, 1);
available = sample_count >= 365 * 24;
if available
    note = "2025 wind and PV data loaded only after metric locking";
else
    note = "2025 renewable files do not contain a complete year";
end
end

function electricity = readRenewableElectricity(file_path)
lines = readlines(file_path);
header_index = find(startsWith(strip(lines), "time,electricity"), 1);
if isempty(header_index)
    error('test_chose_index:renewable_header', ...
        'Cannot find time,electricity header in %s.', file_path);
end
options = detectImportOptions(file_path, ...
    'NumHeaderLines', header_index - 1);
data = readtable(file_path, options);
electricity_name = string(data.Properties.VariableNames(...
    strcmpi(data.Properties.VariableNames, 'electricity')));
if isempty(electricity_name)
    error('test_chose_index:renewable_column', ...
        'Cannot find electricity column in %s.', file_path);
end
electricity = data.(char(electricity_name(1)));
electricity = electricity(isfinite(electricity));
end

function forcing_bank = buildHoldoutForcingBank(...
        forcing, sample_count, schedule_count)
forcing = forcing(:);
forcing_bank = zeros(sample_count, schedule_count);
maximum_start = numel(forcing) - sample_count + 1;
starts = round(linspace(1, maximum_start, schedule_count));
for schedule_index = 1:schedule_count
    rows = starts(schedule_index):...
        (starts(schedule_index) + sample_count - 1);
    forcing_bank(:, schedule_index) = forcing(rows);
end
end

function checksum = vectorChecksum(values)
checksum = protocolChecksum(struct('Values', values));
end

function step = buildEngineeringResponseMap(...
        protocol, locked, holdout, redundancy, robustness)
registry = protocol.Registry;
step.action_map = registry(:, {'Name', 'Family', 'EngineeringAction', ...
    'PotentialSideEffect', 'OptimizationMapping', ...
    'InterpretabilityScore', 'ActionabilityScore'});
core_names = locked.selection.Name(...
    locked.selection.Decision == "core");
step.core_action_map = step.action_map(...
    ismember(step.action_map.Name, core_names), :);
families = unique(registry.Family, 'stable');
candidate_count = zeros(numel(families), 1);
validity_pass_count = zeros(numel(families), 1);
robust_count = zeros(numel(families), 1);
eligible_count = zeros(numel(families), 1);
selected_metric = repmat("none", numel(families), 1);
for family_index = 1:numel(families)
    rows = locked.selection.Family == families(family_index);
    candidate_count(family_index) = sum(rows);
    validity_pass_count(family_index) = ...
        sum(locked.selection.ValidityPass(rows));
    robust_count(family_index) = sum(locked.selection.Robust(rows));
    eligible_count(family_index) = sum(locked.selection.Eligible(rows));
    selected = locked.selection.Name(rows & ...
        (locked.selection.Decision == "core" | ...
        locked.selection.Decision == "provisional"));
    if ~isempty(selected)
        selected_metric(family_index) = selected(1);
    end
end
step.family_gate_audit = table(families, candidate_count, ...
    validity_pass_count, robust_count, eligible_count, selected_metric, ...
    'VariableNames', {'Family', 'CandidateCount', 'ValidityPassCount', ...
    'RobustCount', 'EligibleCount', 'SelectedMetric'});
upper_dimensions = unique(registry.UpperDimension, 'stable');
dimension_eligible_count = zeros(numel(upper_dimensions), 1);
dimension_selected_count = zeros(numel(upper_dimensions), 1);
for dimension_index = 1:numel(upper_dimensions)
    rows = locked.selection.UpperDimension == ...
        upper_dimensions(dimension_index);
    dimension_eligible_count(dimension_index) = ...
        sum(locked.selection.Eligible(rows));
    dimension_selected_count(dimension_index) = sum(rows & ...
        (locked.selection.Decision == "core" | ...
        locked.selection.Decision == "provisional"));
end
step.upper_dimension_audit = table(upper_dimensions, ...
    dimension_eligible_count, dimension_selected_count, ...
    'VariableNames', {'UpperDimension', 'EligibleCount', ...
    'SelectedOrProvisionalCount'});
step.metric_gate_audit = buildMetricDiagnosticAudit(...
    protocol, locked.selection, redundancy, robustness);
gate = ["mandatory_deterministic"; "other_deterministic"; ...
    "Cliffs_delta"; "Spearman"; "Kendall"; "redundancy"; ...
    "incremental_information"; "engineering"; "core_functional_position"];
failure_count = [sum(~locked.selection.MandatoryDeterministicPass); ...
    sum(~locked.selection.OtherDeterministicPass); ...
    sum(~locked.selection.EffectPass); ...
    sum(~locked.selection.MonotonicityPass); ...
    sum(~locked.selection.Robust); ...
    sum(~locked.selection.RedundancyPass); ...
    sum(~locked.selection.IncrementalInformationPass); ...
    sum(~locked.selection.EngineeringRulePass); ...
    sum(~locked.selection.CoreEligible)];
step.gate_failure_summary = table(gate, failure_count, ...
    'VariableNames', {'Gate', 'FailedMetricCount'});
step.holdout_status = holdout.status;
step.complete = ~any(ismissing(step.action_map.EngineeringAction)) && ...
    ~any(ismissing(step.action_map.PotentialSideEffect)) && ...
    ~any(ismissing(step.action_map.OptimizationMapping));
end

function audit = buildMetricDiagnosticAudit(...
        protocol, selection, redundancy, robustness)
metric_count = height(selection);
tau_threshold = nan(metric_count, 1);
tau_quantile = nan(metric_count, 1);
tau_window = nan(metric_count, 1);
tau_sampling = nan(metric_count, 1);
worst_setting = strings(metric_count, 1);
pairwise_agreement = nan(metric_count, 1);
redundancy_partner = repmat("none", metric_count, 1);
first_failed_gate = strings(metric_count, 1);

for metric_index = 1:metric_count
    metric = selection.Name(metric_index);
    hard_rows = robustness.results.Metric == metric;
    hard_results = robustness.results(hard_rows, :);
    sensitivity_rows = robustness.sensitivity_results.Metric == metric;
    sensitivity_results = ...
        robustness.sensitivity_results(sensitivity_rows, :);
    tau_threshold(metric_index) = minimumTau(hard_results, ...
        ["low_load_threshold"; "min_dwell_hours"]);
    tau_quantile(metric_index) = minimumTau(...
        hard_results, "tail_percentile");
    tau_window(metric_index) = minimumTau(...
        hard_results, "window_hours");
    tau_sampling(metric_index) = minimumTau(...
        sensitivity_results, "sampling_hours");
    if isempty(hard_results)
        worst_setting(metric_index) = "not_applicable_fixed_definition";
        pairwise_agreement(metric_index) = 1;
    else
        [~, worst_index] = min(hard_results.KendallTau);
        worst_setting(metric_index) = ...
            hard_results.Parameter(worst_index) + "=" + ...
            string(hard_results.ParameterValue(worst_index));
        pairwise_agreement(metric_index) = ...
            min(hard_results.PairwiseAgreement);
    end
    redundancy_partner(metric_index) = findRedundancyPartners(...
        redundancy.flagged_pairs, metric);
    first_failed_gate(metric_index) = ...
        firstFailedGate(selection, metric_index);
end

audit = table(selection.Name, selection.UpperDimension, ...
    selection.Family, selection.MandatoryDeterministicPass, ...
    selection.OtherApplicablePassRate, selection.CliffsDelta, ...
    selection.CohenD, selection.TargetFeature, ...
    selection.MonotonicityRho, tau_threshold, tau_quantile, ...
    tau_window, tau_sampling, worst_setting, pairwise_agreement, ...
    redundancy_partner, selection.IncrementalR2, first_failed_gate, ...
    selection.Eligible, 'VariableNames', {'Metric', 'UpperDimension', ...
    'Family', 'MandatoryPass', 'OtherDeterministicRate', ...
    'CliffsDelta', 'CohenD', 'MonotonicityTarget', ...
    'MonotonicityRho', 'TauThreshold', 'TauQuantile', 'TauWindow', ...
    'TauSampling', 'WorstSetting', 'PairwiseAgreement', ...
    'RedundancyPartner', 'IncrementalR2', 'FirstFailedGate', ...
    'Eligible'});
audit.Properties.UserData = struct(...
    'Seal', protocol.Seal, ...
    'PairwiseAgreementRole', "diagnostic_only_not_a_gate", ...
    'TauSensitivityRole', "threshold_quantile_window_are_hard_only_when_" + ...
        "listed_in_v4_applicability; sampling_is_diagnostic_only");
end

function value = minimumTau(results, parameters)
rows = ismember(results.Parameter, parameters);
if any(rows)
    value = min(results.KendallTau(rows));
else
    value = NaN;
end
end

function partners = findRedundancyPartners(flagged_pairs, metric)
if isempty(flagged_pairs)
    partners = "none";
    return
end
partner_names = strings(0, 1);
first_rows = flagged_pairs.FirstMetric == metric;
second_rows = flagged_pairs.SecondMetric == metric;
partner_names = [partner_names; ...
    flagged_pairs.SecondMetric(first_rows); ...
    flagged_pairs.FirstMetric(second_rows)];
if isempty(partner_names)
    partners = "none";
else
    partners = strjoin(unique(partner_names, 'stable'), ';');
end
end

function gate = firstFailedGate(selection, metric_index)
gate_names = ["MandatoryPass"; "OtherDeterministicRate"; ...
    "CliffsDelta"; "MonotonicityRho"; "Kendall"; ...
    "Redundancy"; "IncrementalR2"; "EngineeringRule"; ...
    "CoreFunctionalPosition"];
gate_values = [selection.MandatoryDeterministicPass(metric_index); ...
    selection.OtherDeterministicPass(metric_index); ...
    selection.EffectPass(metric_index); ...
    selection.MonotonicityPass(metric_index); ...
    selection.Robust(metric_index); ...
    selection.RedundancyPass(metric_index); ...
    selection.IncrementalInformationPass(metric_index); ...
    selection.EngineeringRulePass(metric_index); ...
    selection.CoreEligible(metric_index)];
failed_index = find(~gate_values, 1);
if isempty(failed_index)
    gate = "none";
else
    gate = gate_names(failed_index);
end
end

function metrics = computeMetrics(load, h2_soc, hb_on, config)
load = load(:);
h2_soc = h2_soc(:);
hb_on = hb_on(:);
if numel(h2_soc) == numel(load) + 1
    h2_soc = h2_soc(2:end);
end
if numel(h2_soc) ~= numel(load) || numel(hb_on) ~= numel(load)
    error('test_chose_index:bad_h2_length', ...
        'H2 SOC must have T or T+1 samples and HB_on must have T samples.');
end
if any(hb_on ~= 0 & hb_on ~= 1)
    error('test_chose_index:bad_hb_state', ...
        'HB_on must be an explicit binary state sequence.');
end

samples_per_window = round(config.window_hours / config.dt);
window_count = floor(numel(load) / samples_per_window);
if window_count < 1
    error('test_chose_index:short_schedule', ...
        'At least one complete assessment window is required.');
end
used_count = window_count * samples_per_window;
window_load = reshape(load(1:used_count), ...
    samples_per_window, window_count);
window_mean = mean(window_load, 1);
deviation = window_load - window_mean;
window_dcv = sqrt(mean(deviation .^ 2, 1));
window_mad = mean(abs(deviation), 1);
window_output = sum(window_load, 1) * config.dt;
mean_output = mean(window_output);
if mean_output <= eps
    output_cv = 0;
    output_max_dev = 0;
    shortfall_p95 = 0;
else
    output_cv = std(window_output, 1) / mean_output;
    output_max_dev = max(abs(window_output - mean_output)) / mean_output;
    shortfall = max(mean_output - window_output, 0) / mean_output;
    shortfall_p95 = prctile(shortfall, config.tail_percentile);
end

ramp = onlineRampValues(load, hb_on, config.dt);
state_boundaries = [1; find(diff(hb_on) ~= 0) + 1; numel(hb_on) + 1];
dwell_hours = diff(state_boundaries) * config.dt;
short_dwell_ratio = sum(dwell_hours(dwell_hours < ...
    config.min_dwell_hours)) / (numel(load) * config.dt);
online = hb_on == 1;
if any(online)
    low_load_ratio = mean(load(online) < config.low_load_threshold);
else
    low_load_ratio = 1;
end

metrics.dcv_mean = mean(window_dcv);
metrics.dcv_p95 = prctile(window_dcv, config.tail_percentile);
metrics.dcv_max = max(window_dcv);
metrics.intraday_mad = mean(window_mad);
metrics.daily_output_cv = output_cv;
metrics.daily_output_max_dev = output_max_dev;
metrics.daily_shortfall_p95 = shortfall_p95;
metrics.low_load_ratio = low_load_ratio;
metrics.mar = mean(ramp);
metrics.rms_ramp = sqrt(mean(ramp .^ 2));
metrics.ramp_p95 = prctile(ramp, config.tail_percentile);
metrics.ramp_max = max(ramp);
metrics.switch_count = sum(abs(diff(hb_on)));
metrics.short_dwell_ratio = short_dwell_ratio;
metrics.h2_soc_p05 = prctile(h2_soc, ...
    100 - config.tail_percentile);
metrics.h2_min_margin = min(h2_soc - config.h2_safe);
metrics.h2_risk_hours = sum(h2_soc < config.h2_safe) * config.dt;
end

function vector = metricVector(load, h2_soc, hb_on, registry, config)
metrics = computeMetrics(load, h2_soc, hb_on, config);
vector = zeros(1, height(registry));
for metric_index = 1:height(registry)
    vector(metric_index) = metrics.(char(registry.Name(metric_index)));
end
end

function matrix = metricMatrix(load, h2_soc, hb_on, registry, config)
matrix = zeros(size(load, 2), height(registry));
for schedule_index = 1:size(load, 2)
    matrix(schedule_index, :) = metricVector(load(:, schedule_index), ...
        h2_soc(:, schedule_index), hb_on(:, schedule_index), ...
        registry, config);
end
end

function ramp = onlineRampValues(load, hb_on, dt)
raw_ramp = abs(diff(load, 1, 1)) / dt;
online_transition = hb_on(1:(end - 1), :) == 1 & ...
    hb_on(2:end, :) == 1;
ramp = raw_ramp(online_transition);
if isempty(ramp)
    ramp = 0;
end
end

function delta = cliffsDelta(high, low)
comparison = high(:) - low(:)';
delta = (sum(comparison > 0, 'all') - ...
    sum(comparison < 0, 'all')) / numel(comparison);
end

function value = cohensD(high, low)
high = high(:);
low = low(:);
pooled_variance = ((numel(high) - 1) * var(high, 0) + ...
    (numel(low) - 1) * var(low, 0)) / ...
    (numel(high) + numel(low) - 2);
if pooled_variance <= eps
    difference = mean(high) - mean(low);
    if abs(difference) <= eps
        value = 0;
    else
        value = sign(difference) * inf;
    end
else
    value = (mean(high) - mean(low)) / sqrt(pooled_variance);
end
end

function [lower, upper] = bootstrapCliffsDelta(...
        high, low, iterations, seed)
old_random_state = rng;
random_cleanup = onCleanup(@() rng(old_random_state));
rng(seed, 'twister');
bootstrap_values = zeros(iterations, 1);
for iteration = 1:iterations
    high_sample = high(randi(numel(high), numel(high), 1));
    low_sample = low(randi(numel(low), numel(low), 1));
    bootstrap_values(iteration) = cliffsDelta(high_sample, low_sample);
end
limits = prctile(bootstrap_values, [2.5, 97.5]);
lower = limits(1);
upper = limits(2);
end

function [load, h2_soc, hb_on] = aggregateSamples(...
        load, h2_soc, hb_on, hours)
if hours == 1
    return
end
usable = floor(size(load, 1) / hours) * hours;
schedule_count = size(load, 2);
load = squeeze(mean(reshape(load(1:usable, :), ...
    hours, [], schedule_count), 1));
h2_soc = squeeze(mean(reshape(h2_soc(1:usable, :), ...
    hours, [], schedule_count), 1));
state_blocks = reshape(hb_on(1:usable, :), hours, [], schedule_count);
hb_on = squeeze(state_blocks(end, :, :));
if size(load, 1) ~= usable / hours
    load = load';
    h2_soc = h2_soc';
    hb_on = hb_on';
end
end

function [tau, baseline_tie_rate, trial_tie_rate, pairwise_agreement] = ...
        rankAgreement(baseline, trial)
baseline = baseline(:);
trial = trial(:);
if all(baseline == baseline(1)) && all(trial == trial(1))
    tau = 1;
elseif all(baseline == baseline(1)) || all(trial == trial(1))
    tau = 0;
else
    tau = corr(baseline, trial, 'Type', 'Kendall', ...
        'Rows', 'complete');
    if ~isfinite(tau)
        tau = 0;
    end
end

comparison_count = 0;
baseline_ties = 0;
trial_ties = 0;
agreement_count = 0;
agreement_denominator = 0;
for first_index = 1:(numel(baseline) - 1)
    for second_index = (first_index + 1):numel(baseline)
        baseline_sign = sign(baseline(first_index) - ...
            baseline(second_index));
        trial_sign = sign(trial(first_index) - trial(second_index));
        comparison_count = comparison_count + 1;
        baseline_ties = baseline_ties + double(baseline_sign == 0);
        trial_ties = trial_ties + double(trial_sign == 0);
        if baseline_sign ~= 0
            agreement_denominator = agreement_denominator + 1;
            agreement_count = agreement_count + ...
                double(baseline_sign == trial_sign);
        end
    end
end
if comparison_count == 0
    baseline_tie_rate = 1;
    trial_tie_rate = 1;
    pairwise_agreement = 1;
else
    baseline_tie_rate = baseline_ties / comparison_count;
    trial_tie_rate = trial_ties / comparison_count;
    if agreement_denominator == 0
        pairwise_agreement = double(all(trial == trial(1)));
    else
        pairwise_agreement = agreement_count / agreement_denominator;
    end
end
end

function value = clamp(value, lower, upper)
value = min(max(value, lower), upper);
end

function printSelectionSummary(study)
selection = study.step11.selection;
core = selection(selection.Decision == "core", ...
    {'UpperDimension', 'Family', 'Name', 'CliffsDelta', 'MonotonicityRho', ...
    'WorstKendallTau', 'IncrementalR2', 'Reason'});
provisional = selection(selection.Decision == "provisional", ...
    {'UpperDimension', 'Family', 'Name', 'CliffsDelta', 'MonotonicityRho', ...
    'WorstKendallTau', 'IncrementalR2', 'Reason'});

fprintf('\n========== Preregistered ammonia stability selection ==========' );
fprintf('\nProtocol seal: %s\n', study.step03.protocol.Seal);
fprintf('Candidates: %d; data-selected core metrics: %d\n', ...
    height(selection), height(core));
fprintf('Lock status: %s\n', study.step11.freeze_status);
fprintf('2025 holdout status: %s\n', study.step12.status);
disp(core);
if ~isempty(provisional)
    fprintf('Provisional family representatives; not a locked core set:\n');
    disp(provisional);
end
fprintf('Frozen-gate audit by construct family:\n');
disp(study.step13.family_gate_audit);
fprintf('Upper-dimension coverage audit:\n');
disp(study.step13.upper_dimension_audit);
fprintf('Failed metrics by explicit gate:\n');
disp(study.step13.gate_failure_summary);
fprintf('Seventeen-metric diagnostic audit (diagnostic fields do not alter gates):\n');
disp(study.step13.metric_gate_audit);
fprintf('Engineering benchmark: %s\n', study.step06.description);
fprintf(['Important: optimal means best under the frozen constructs, ', ...
    'thresholds, and benchmark set; it is not a universal optimum.\n']);
fprintf('===============================================================\n');
end
