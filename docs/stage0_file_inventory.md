# Stage 0 File Inventory

Generated: 2026-08-26 11:34:41

This inventory separates source, tests, raw input data, generated results, and documentation for reproducible review.

## Summary

| Category | Role | File count |
|---|---|---:|
| data | data_artifact | 2 |
| data | raw_input | 8 |
| docs | documentation | 9 |
| docs | protocol | 1 |
| paper_outputs | generated_paper_output | 7 |
| project | project_config | 2 |
| runs | generated_result | 204 |
| source | source_code | 35 |
| test | test_artifact | 4 |
| test | test_code | 7 |

## Core Files

- `data/renewables_ninja/2022PV.csv` [data, raw_input] SHA256 `6b9bd9cbd87025f55d96e67b30366bfa91a19224bee29636683c849c31d5bb6c`
- `data/renewables_ninja/2022PW.csv` [data, raw_input] SHA256 `94ac60b946d18b15b486ad59e33e5a07d57683202516988b7f39ada70dd69fa1`
- `data/renewables_ninja/2023PV.csv` [data, raw_input] SHA256 `4b947ae363ce11568e33aed4b912186ac361750eebb3fd95fcc9c875a9cfddb3`
- `data/renewables_ninja/2023PW.csv` [data, raw_input] SHA256 `8173421076ab98027199ec6ef864eaa62f6298014fe7f72e2a3ea58b2a18093e`
- `data/renewables_ninja/2024PV.csv` [data, raw_input] SHA256 `6f4ca83d35cccc9c85893040db8352ccdcef5e7a04d3c4b60629352266751038`
- `data/renewables_ninja/2024PW.csv` [data, raw_input] SHA256 `1ebc2d327946adaf3a5616c52faabfb5b3af75782f0bb49da6b09de98da0b222`
- `data/renewables_ninja/2025PV.csv` [data, raw_input] SHA256 `5f4af48daac6363e3ae9c6e2e93ff2f8b76e8f006baf537d2193609e9a46e669`
- `data/renewables_ninja/2025PW.csv` [data, raw_input] SHA256 `720b2e573d3374fe7bd04bfa81fe13717ac46ca77184ae8be292cc071cbf9760`
- `docs/protocol_v5.md` [docs, protocol] SHA256 `3101b7d134d5536966ee82663262323e40b2120e3df7527441b81085fda5037c`
- `src/baseline.m` [source, source_code] SHA256 `272ccf9343348b3678ce86aad491f10eec3625a18d321991d6a251ab69e7dda5`
- `src/dispatch_model.m` [source, source_code] SHA256 `461f9bf44ba5d5daf4153cefb39af1540327eb6b98fe1abf0d273457c5c75634`
- `src/figures/plot_figure.m` [source, source_code] SHA256 `6976605d57ed260d23d4a8fa35a3692677caf08f251135f3d5ac55b2d555d917`
- `src/figures/thermod.m` [source, source_code] SHA256 `8f5f62145e54812020d9f9d8ea484aeb7a86a4244042d96d8aa374a6251fd1ac`
- `src/load_res_year.m` [source, source_code] SHA256 `1e149aee47f932995b3460c167d99a0e812bc6016ac78a8bd8bec11fd4932cfa`
- `src/main.m` [source, source_code] SHA256 `30930d968ba3be1062e539a4495cf6caba6a66b000f784cc08d5a624e97dab77`
- `src/paper/export_main_figures.m` [source, source_code] SHA256 `c2145ea90d3b50539a49631a7c036a442901b4cfa29938da4419e6e0abf04cc6`
- `src/paper/export_main_tables.m` [source, source_code] SHA256 `66d319b9424f47a0b733fbfdd57fc065eddd4fce206c64ed20f579a345ccc067`
- `src/params/AEL.m` [source, source_code] SHA256 `145c11bac3f6ab12cc43c515408533478c9e76e7febe99d0fdc5217d88a8bf5e`
- `src/params/HB.m` [source, source_code] SHA256 `a2b83c0a73c385c673938393d45ae561972933116e59fe6f53474be5ffc2f261`
- `src/params/default.m` [source, source_code] SHA256 `6c67c746c1117ffa637b3c2b6778c4bb021275441896095e5faecff0477e5804`
- `src/params/h2_storage_limits.m` [source, source_code] SHA256 `01f4fa82bb4f414e2d3a4af66f8bb6bb1d2fe8804cecb5570b004d78951556bf`
- `src/params/my_system.m` [source, source_code] SHA256 `aabaa6e75a61ee9bc5f1fd7380d51f122768ee8da61fa96ec4be062e05bbd140`
- `src/pipeline/run_full_tests.m` [source, source_code] SHA256 `4c5359f9a93e262be60a7c50edf059bc4331de74639ab6803e886b2ab64cfc91`
- `src/pipeline/run_quick_tests.m` [source, source_code] SHA256 `b043c0d127705c13c04dfd375e116798c1368fe369ad0beb8f5e299e0104353c`
- `src/pipeline/run_reproduce_core_results.m` [source, source_code] SHA256 `1626daef9dc10ea86d0239ad090470b403fcef0831eee463ced38f6c1588fe66`
- `src/pipeline/run_reproduce_full_grid.m` [source, source_code] SHA256 `3c13009399348b760f9d1523642563f41f282a0c176bdd337d42cdeae8e3e9ea`
- `src/pipeline/run_stage0_quality_gate.m` [source, source_code] SHA256 `7add7fb80cee0e9320bf48dacca0875b856f39087d17ccf75371a3ce932fc3f4`
- `src/protocol/protocol_v5.m` [source, source_code] SHA256 `759caf3be4299115a00d288f94e75f873f0a749e484886757db22c6bb22389d6`
- `src/protocol/s2_baseline_manifest.m` [source, source_code] SHA256 `c27f5ff528f7ef87aa6078dae6e5dbde5a13f22a5e4bd62ad76336944e71b26d`
- `src/reproducibility/stage0_constraint_audit.m` [source, source_code] SHA256 `26b68997659a787fba75e8d53500a2b561ad783c511b383b822063c6c508442f`
- `src/reproducibility/stage0_manifest.m` [source, source_code] SHA256 `27a374c5b3b521b70e91c15a44b0ece3008a6db2891015d1e06155769583fa08`
- `src/results/annual_fixed_cost.m` [source, source_code] SHA256 `a7b78fc822b1847a35a7a4e5aaf7806db7b05baa980e8c1f07bb9402cf5f67ad`
- `src/results/evaluate_protocol_v51_metrics.m` [source, source_code] SHA256 `4abf9f86a6de08d2846ed813dab28c83c3fc488cff90e72b86fefcc33a6b5b5a`
- `src/results/freeze_v51_rolling_result.m` [source, source_code] SHA256 `a5bec7cb66d2cac4894670b52b0b3b59c37ecedf3a332be5c11d5d78219ab000`
- `src/results/result_LCOA.m` [source, source_code] SHA256 `ec8b84ae67025450c909bdb24ab34776e463e5b8501b2db6f649468501540742`
- `src/results/results.m` [source, source_code] SHA256 `23bf1cdb0ef55d024b0c2216d8d332ce34ca218a8f37979ea3c20301509a8be6`
- `src/rolling_dispatch.m` [source, source_code] SHA256 `988cb1c59ec36cb39553eed3a057e30d6477a3bcd1147dc93cda455d60874f22`
- `src/stage0_freeze_check.m` [source, source_code] SHA256 `ddb23691b6d48b781f1f460409c3acd3f321d83812589fdb3fa35bd14852bf88`
- `src/stage1_run_zhou_s2_baseline.m` [source, source_code] SHA256 `f0270a2f0a6dd57d374844eedb1b8697cbc4bbfe31df52120415cc70bd64207e`
- `src/stage3_run_v51_contract_closed_loop.m` [source, source_code] SHA256 `e00e3fbecc2799f092280b3fbfceba74ecbd72bb280b68eb9834cd34cb6cde5b`
- `src/stage4_run_v51_h2_reserve_grid.m` [source, source_code] SHA256 `b2a4d114507af69622d8e1fac50dff80827c2b90d1603343a44dad188b62612b`
- `src/stage5_run_v51_joint_grid.m` [source, source_code] SHA256 `f1edca5dd46be2b7397e86e5c65cadbd97f8c7441a03fdcd2266695ec7cb137d`
- `src/utils/project_root.m` [source, source_code] SHA256 `74e24cc87256c1f7fdc3cf831656d127e2911bf7122ff3fe3c7091dfa444adae`
- `src/utils/setup_project_paths.m` [source, source_code] SHA256 `bce35bde3bde987baaee4fe41ed877b395e66e644bec0a7d3503cf772bc1dc25`
- `test/test_CI_vertify.m` [test, test_code] SHA256 `5e11a5c7e03fc29f797cffd01cf7bc25b8118adcfd513d011a0dd341e491709b`
- `test/test_chose_index.m` [test, test_code] SHA256 `f15342914299527034eacc77ca255ed76eed30fc8b38f2a3e9d47a415d61cab4`
- `test/test_load_res_year.m` [test, test_code] SHA256 `7c8b38915464e3e4756fda1c51156706b5788d261e05163c6171310a0e549700`
- `test/test_my_system.m` [test, test_code] SHA256 `561d90226361253187a343b0d7c4e030f041e240a7a6f6048b4e525e054141ff`
- `test/test_protocol_v5.m` [test, test_code] SHA256 `715cb07abe0f884f9ef77bafba3358d77c8e4cc37a0439197a9f900fe73ea9c2`
- `test/test_stage0_reproducibility.m` [test, test_code] SHA256 `d0aac67052e48a6f78b660fb3c8ecdffbaecf16745b4a43b6881b1c7605250b7`
- `test/test_stage0_stage1.m` [test, test_code] SHA256 `fc602120d0916e6f3486104c04adcc3322fd662b9b87499e84c68eccb405612c`
