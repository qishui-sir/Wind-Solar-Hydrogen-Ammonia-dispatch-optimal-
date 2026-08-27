# Stage 0 File Inventory

Generated: 2026-08-26 16:39:23

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
| source | source_code | 38 |
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
- `docs/protocol_v5.md` [docs, protocol] SHA256 `eb4be18f7e079f66a50da9453330631da7bf10f2cab31570c7034d873e9dd790`
- `src/baseline.m` [source, source_code] SHA256 `272ccf9343348b3678ce86aad491f10eec3625a18d321991d6a251ab69e7dda5`
- `src/dispatch_model.m` [source, source_code] SHA256 `461f9bf44ba5d5daf4153cefb39af1540327eb6b98fe1abf0d273457c5c75634`
- `src/figures/plot_figure.m` [source, source_code] SHA256 `6976605d57ed260d23d4a8fa35a3692677caf08f251135f3d5ac55b2d555d917`
- `src/figures/thermod.m` [source, source_code] SHA256 `8f5f62145e54812020d9f9d8ea484aeb7a86a4244042d96d8aa374a6251fd1ac`
- `src/load_res_year.m` [source, source_code] SHA256 `1e149aee47f932995b3460c167d99a0e812bc6016ac78a8bd8bec11fd4932cfa`
- `src/main.m` [source, source_code] SHA256 `30930d968ba3be1062e539a4495cf6caba6a66b000f784cc08d5a624e97dab77`
- `src/paper/export_main_figures.m` [source, source_code] SHA256 `bfd6c1aa6212d407bb52348dde4357acd3b80a2bc1ddc996ea82ef535af1b690`
- `src/paper/export_main_tables.m` [source, source_code] SHA256 `a5a63d2f79dd51528b5decc0699856dd9029bc62ebf71f35918d80be76b835ea`
- `src/params/AEL.m` [source, source_code] SHA256 `145c11bac3f6ab12cc43c515408533478c9e76e7febe99d0fdc5217d88a8bf5e`
- `src/params/HB.m` [source, source_code] SHA256 `a2b83c0a73c385c673938393d45ae561972933116e59fe6f53474be5ffc2f261`
- `src/params/default.m` [source, source_code] SHA256 `6c67c746c1117ffa637b3c2b6778c4bb021275441896095e5faecff0477e5804`
- `src/params/h2_storage_limits.m` [source, source_code] SHA256 `01f4fa82bb4f414e2d3a4af66f8bb6bb1d2fe8804cecb5570b004d78951556bf`
- `src/params/my_system.m` [source, source_code] SHA256 `aabaa6e75a61ee9bc5f1fd7380d51f122768ee8da61fa96ec4be062e05bbd140`
- `src/pipeline/run_full_tests.m` [source, source_code] SHA256 `765ef52bc9ce0a7c3d6dde9e2b7b5b6ad54b27006bf8491e8cb7bdda5222dc5e`
- `src/pipeline/run_quick_tests.m` [source, source_code] SHA256 `23085551f93021262cbca24b1d859da1566d75bcc4992a59193faeccf77da90e`
- `src/pipeline/run_reproduce_core_results.m` [source, source_code] SHA256 `45833f0b3bb71869d60e773be0f7e90e89618987150cbc625da20d999e358e72`
- `src/pipeline/run_reproduce_full_grid.m` [source, source_code] SHA256 `7be13ed5eb66c1b7574b6897e8f17a0e3e2ab78a4040915eeb63ac66e9669444`
- `src/pipeline/run_stage0_quality_gate.m` [source, source_code] SHA256 `53a67e3dce8c2a1b67383b0fdd3df3640c4d2e84be85eea9afa45951c10d9bf1`
- `src/protocol/protocol_v5.m` [source, source_code] SHA256 `0cd46c864adcf7ffc0c1b1a268f34e8ea04455cbf0c1dbbff868b21fcddbe107`
- `src/protocol/s2_baseline_manifest.m` [source, source_code] SHA256 `c27f5ff528f7ef87aa6078dae6e5dbde5a13f22a5e4bd62ad76336944e71b26d`
- `src/reproducibility/stage0_constraint_audit.m` [source, source_code] SHA256 `26b68997659a787fba75e8d53500a2b561ad783c511b383b822063c6c508442f`
- `src/reproducibility/stage0_freeze_check.m` [source, source_code] SHA256 `e9df9b1cdcfdcad3c22a1cb3395a33b57d07031b35d69f0f358d3f77bb19687a`
- `src/reproducibility/stage0_manifest.m` [source, source_code] SHA256 `27a374c5b3b521b70e91c15a44b0ece3008a6db2891015d1e06155769583fa08`
- `src/results/annual_fixed_cost.m` [source, source_code] SHA256 `a7b78fc822b1847a35a7a4e5aaf7806db7b05baa980e8c1f07bb9402cf5f67ad`
- `src/results/evaluate_protocol_v51_metrics.m` [source, source_code] SHA256 `4abf9f86a6de08d2846ed813dab28c83c3fc488cff90e72b86fefcc33a6b5b5a`
- `src/results/freeze_v51_rolling_result.m` [source, source_code] SHA256 `a5bec7cb66d2cac4894670b52b0b3b59c37ecedf3a332be5c11d5d78219ab000`
- `src/results/result_LCOA.m` [source, source_code] SHA256 `ec8b84ae67025450c909bdb24ab34776e463e5b8501b2db6f649468501540742`
- `src/results/results.m` [source, source_code] SHA256 `23bf1cdb0ef55d024b0c2216d8d332ce34ca218a8f37979ea3c20301509a8be6`
- `src/results/select_protocol_v52_candidate.m` [source, source_code] SHA256 `453c2f5cb44337670db3d5f6952a1656e341fc2c4f4606b7eb1afac0e845ff22`
- `src/rolling_dispatch.m` [source, source_code] SHA256 `988cb1c59ec36cb39553eed3a057e30d6477a3bcd1147dc93cda455d60874f22`
- `src/stages/stage1_run_zhou_s2_baseline.m` [source, source_code] SHA256 `90f5343d542bbaadf0858a9dcb50b0e0cb9a993bba26ae1b433e7ec9c46c4251`
- `src/stages/stage3_run_v51_contract_closed_loop.m` [source, source_code] SHA256 `cceecd4734188e38893de4e87c10298a9842df290d0683445cec27b49e158a70`
- `src/stages/stage4_run_v51_h2_reserve_grid.m` [source, source_code] SHA256 `f2a9db1894c9b33aa3ee0fbda09d97602063bddddd3248d9d8a180b340b251a5`
- `src/stages/stage5_run_v51_joint_grid.m` [source, source_code] SHA256 `0c9c1c784310b8310f500c5493cb0e5f02160f8b9467dd3c20b1a9b67d3d21af`
- `src/utils/ensure_directory.m` [source, source_code] SHA256 `6e119d33237f9eacb1ec4324b862dd6de0aaf0b00c6419bdd98dc032cf27d72e`
- `src/utils/option_value.m` [source, source_code] SHA256 `bec6c67f114f88480f6c50e74f7e70690887109145688f1a3ec3c18e3580c029`
- `src/utils/project_root.m` [source, source_code] SHA256 `74e24cc87256c1f7fdc3cf831656d127e2911bf7122ff3fe3c7091dfa444adae`
- `src/utils/setup_project_paths.m` [source, source_code] SHA256 `27ba35f7f7344309b20d01ea4178d5d093f829bf1b9c88643166fa37df6b3696`
- `test/test_CI_vertify.m` [test, test_code] SHA256 `5e11a5c7e03fc29f797cffd01cf7bc25b8118adcfd513d011a0dd341e491709b`
- `test/test_chose_index.m` [test, test_code] SHA256 `f15342914299527034eacc77ca255ed76eed30fc8b38f2a3e9d47a415d61cab4`
- `test/test_load_res_year.m` [test, test_code] SHA256 `7c8b38915464e3e4756fda1c51156706b5788d261e05163c6171310a0e549700`
- `test/test_my_system.m` [test, test_code] SHA256 `561d90226361253187a343b0d7c4e030f041e240a7a6f6048b4e525e054141ff`
- `test/test_protocol_v5.m` [test, test_code] SHA256 `666dfc933e0ef6b3b3c35ae926b7804a983259d3c3c36ab571df2153dc020fee`
- `test/test_stage0_reproducibility.m` [test, test_code] SHA256 `d0aac67052e48a6f78b660fb3c8ecdffbaecf16745b4a43b6881b1c7605250b7`
- `test/test_stage0_stage1.m` [test, test_code] SHA256 `4edc0918f9cf0aebe5261b033d9028fda90bbee1169a2d26a813eb721c0ac560`
