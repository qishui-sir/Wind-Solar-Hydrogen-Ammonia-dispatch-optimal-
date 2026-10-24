# 调度研究结果索引

更新：2026-10-21。当前图表按用户指定使用 MATLAB 绘制，遵循 Nature skills 的数据完整性、统一配色、物理尺寸和渲染核验原则。

## 当前结果

[Paper4正文图1—3](paper4_figures_01_03_20261021/README.md)：系统与计数定义、经济性与阶段认证边界、全年调整结构及循环平台分布；包含MATLAB源代码、精确源表、英文图注和渲染核验。

[K=487 全年调度与月度比较](K487_annual_dispatch_20261020/README.md) 为当前可核验的研究结果入口。两条轨迹均为2022年完整8760小时、同设备、同产量和同跟踪带；参考轨迹计数4029，经济合格见证计数487。

- [月购售电比较](K487_annual_dispatch_20261020/figures/comparisons/04_monthly_grid_comparison.png)
- [HB月负荷比较](K487_annual_dispatch_20261020/figures/comparisons/05_monthly_HB_comparison.png)
- [月度精确源数据](K487_annual_dispatch_20261020/data/monthly_comparison.csv)
- [图注、统计口径与核验说明](K487_annual_dispatch_20261020/reports/REPORT_月度比较图.md)

## 目录规则

```text
results_out/
├─ README.md
├─ K487_annual_dispatch_20261020/
│  ├─ README.md
│  ├─ REPORT_全年调度.md
│  ├─ data/                 小时、库存、事件、日/月/年表及参考轨迹
│  ├─ models/               原始MAT解、验证矩阵和历史图元信息
│  ├─ scripts/              MATLAB数据准备/导出/绘图及整理脚本
│  ├─ figures/
│  │  ├─ annual/            既有全年图、关键周图和热图
│  │  └─ comparisons/       本次两幅月度比较图
│  ├─ reports/              汇总、独立验收、图表核验、迁移记录
│  │  ├─ figure_qa/         对齐、字号、碰撞检查及诊断覆盖图
│  │  └─ history/           旧哈希清单等历史记录
│  └─ logs/                 导出日志
└─ archive/
   ├─ reserve_scan_202609/   旧储氢扫描结果
   └─ diagnostics_202609/    旧固定K种子与诊断日志
```

旧文件分类归档，未删除或覆盖；整理时逐文件核对内容哈希。一个例外是用户修改过的 `comparison_with_reference.csv` 正被其他程序占用，原件保留在案例根目录，`data/` 中存放内容哈希完全相同的副本。关闭该文件后如需收拢，可先确认两者内容仍相同，再自行移走根目录原件。旧文稿中 `results_out/reserve_*` 对应现在的 `archive/reserve_scan_202609/`，`diag_*`、`o1_direct.log` 和 `O1_K365_feasible_seed.mat` 对应 `archive/diagnostics_202609/`。完整旧路径到新路径映射见当前案例的 `reports/REORGANIZATION_20261021.json`。

旧扫描及种子属于历史模型/求解记录，不自动构成本次同口径的最优成本对照。当前487次轨迹仍是经济可行见证，并未证明其固定次数成本最优。
