> Historical snapshot: superseded by `../v52_negative_evidence_freeze.md`.
> Positive claims below are preserved for provenance and are not current conclusions.

# 论文贡献叙事与 HB 平滑因果定稿（一页）

> 用途：写论文前先钉死这三件事——(1) HB 平滑的因果表述红线；(2) 论文贡献
> 与主张强度；(3) Methods 必须逐条写的披露清单。任何偏离本页的表述都要先回
> 协议或重跑，不能临时改口径。

## 1. HB 平滑的因果澄清（红线，写进 Methods + Discussion）

**事实**：`hb_smoothing_reduction_fraction = s` 在
`apply_joint_coordination_params` 里直接执行
`params.HB.ramp_rate = 0.20 * (1 - s)`，即把 HB 每小时爬坡上限从 20% 收紧到
`20%×(1−s)`。因此 MAR（`mean|ΔHB_load|`）下降约 20% 在很大程度上是**爬坡上界
被收紧的机械后果**，不是调度策略在同一边界下"更聪明"的涌现改进。

**推荐表述（方案 A，不动模型）**：

> HB smoothing is implemented as a deliberate tightening of the hourly
> ramp-rate limit from 20%/h to 20%×(1−s)/h. Consequently the reported MAR
> reduction is, in part, the direct mechanical effect of the tighter ramp
> bound rather than an emergent property of the scheduling policy. We
> therefore report it as a *stability-at-the-cost-of-flexibility* tradeoff,
> not as a like-for-like dispatch improvement.

**禁止表述**：

- "HB smoothing reduces HB ramping without sacrificing flexibility"
- "the coordinated policy improves HB stability at equal ramp capability"
- 任何把 MAR 改善写成"调度算法优越性"的句子。

**可选升级（方案 B，若冲一区且有时间）**：把硬爬坡上限改为爬坡超限的软惩罚
项（soft penalty），使 MAR 下降成为调度选择而非约束改变。需改
`apply_joint_coordination_params` + 重跑关键候选，2–3 个月预算内**不建议**。

## 2. 论文定位与一句话贡献

**主张强度**：`cost_bounded_stability_noninferiority`（成本有界稳定性非劣），
不是"明确优于基线"。协议 v5.2 已锁定，照此执行。

**一句话贡献**：

> 面向固定容量风光制氢制氨系统，提出并验证一套"日前 72 h 计划 + 实时回放"
> 的滚动 MILP 协调框架，联合年度合同进度、碳/电网年度预算可达性与预测驱动
> 氢储备门控，在冻结的可复现协议下定量刻画了"以约 0.4% 合同尾部风险与 0.1%
> LCOA 为代价、换取 HB 小时爬坡强度约 20% 下降与氢库存下尾储备抬升"的成本有
> 界权衡。

**三条贡献 bullet**：

1. **协调框架**：合同进度 + 年度碳/售/弃预算可达性 + 氢储备门控的联合滚动
   MPC，含严格 FIFO 交付、不可行层级回退（碳债→产氨偏差→经济）与状态交接。
2. **定量权衡刻画**：在相同年度合同与物理边界下，给出成本/合同尾部风险/
   HB 爬坡/氢库存下尾四维的非支配权衡面，而非单一加权最优。
3. **可复现性治理**：协议冻结 + 校验码 + 逐结果约束残差审计 + 质量门，为
   能源系统优化提供可复现范式（审稿人高度认可的差异化卖点）。

## 3. 标题候选

- **主推**：*Cost-bounded rolling coordination of contract, carbon budget,
  and hydrogen reserve for a wind–solar–hydrogen–ammonia plant*
- 备选：*Day-ahead scheduling with contract, carbon-budget, and hydrogen-reserve
  coordination under a firm ammonia contract*

## 4. Methods 必写披露清单（逐条，不合并不省略）

1. 预测为**模拟环境**：日前 persistence（无未来泄漏），非真实 NWP/第三方预测。
2. `observed_oracle` 仅为**完美信息上界诊断**，不作运行预测性能证据。
3. 储氢压力按**绝压**解释，表压敏感性单独报告。
4. 可再生缩放因子 `0.8623` 为**未充分解释的校准因子**。
5. 容量配比 **200 MW PV + 200 MW PW**，非 Zhou 的 100/300 参考配比。
6. AEL 启动耗电采用 **S3 参数用于 S2** 的研究覆盖。
7. 数据为 Renewables.ninja/MERRA2 **再分析**（非实测功率与日前预测成对）。
8. 2024 校准因计算预算采用**缩减网格**（完整 156 网格在 2022 开发年已报告）。
9. 滚动层 gap 1e-3 / 年度层 1e-4，求解精度敏感性单独报告。

## 5. Results 叙事顺序

1. **2022 基准 + 诊断**：Zhou S2 复现（LCOA 465.18）+ 基线贴储氢下限 4935 h。
2. **协调机制逐项贡献**：合同 / 碳预算 / 氢储备门控各自对可行性与指标的边际。
3. **2024 校准网格 + v5.2 选择审计**：冻结字典序选点，完整网格报告。
4. **2025 锁定测试**：一次性、不调参，确认或记录负结果。
5. **敏感性**：表压 / 求解精度 / （可选）储氢容量与延期窗口。

## 6. 期刊匹配与上探条件

- **主线（稳）**：International Journal of Hydrogen Energy、Renewable Energy
  ——绿氢绿氨 + 协调调度 + 可复现性最对口。
- **上探（有条件）**：Energy Conversion and Management——需 persistence 结果
  漂亮、敏感性干净，且叙事重心落在"协调框架 + 可复现性"而非"预测性能"。
- **不建议**：Applied Energy——无真实预测数据，实用价值证据不足，大概率拒。
