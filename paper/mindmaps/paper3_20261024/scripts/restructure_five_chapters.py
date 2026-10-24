"""将原脑图七章内容无损重排为五章，保留旧XMind于history。"""
from pathlib import Path
from copy import deepcopy
import re
import shutil

BASE = Path(__file__).resolve().parents[1]
path = BASE / "脑图内容源稿.md"
sheets, stack = [], []
for line in path.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    if line.startswith("# "):
        sheet = {"title": line[2:], "roots": []}
        sheets.append(sheet)
        stack = []
        continue
    m = re.fullmatch(r"( *)- (.+)", line)
    assert m
    depth = len(m[1]) // 2
    stack = stack[:depth]
    node = {"title": m[2], "children": []}
    (stack[-1]["children"] if stack else sheet["roots"]).append(node)
    stack.append(node)

detail_root = sheets[1]["roots"][0]
if len(detail_root["children"]) == 5:
    print("Already five chapters; no outline rewrite")
    raise SystemExit(0)
assert len(detail_root["children"]) == 7
history = BASE / "history"
history.mkdir(exist_ok=True)
old_file = BASE / "paper3_论文框架与证据路线_详细脑图.xmind"
archived = history / "paper3_七章版_20261024.xmind"
if old_file.exists() and not archived.exists():
    shutil.copyfile(old_file, archived)


def node(title, children=()):
    return {"title": title, "children": [deepcopy(c) if isinstance(c, dict) else node(c) for c in children]}


def rename(n, title):
    item = deepcopy(n)
    item["title"] = title
    return item


overview = sheets[0]["roots"][0]
old_overview = overview["children"]
overview_four = node("第4章 结果与讨论", [
    "4.1 算例设置与数据", "4.2 最低更新需求的认证结果", "4.3 经济预算—最低需求关系",
    "4.4 同口径策略对照及文献联系", "4.5 调度特征与代价转移", "4.6 储氢替代机制",
    "4.7 补氢能力与电网反事实", "4.8 敏感性与适用范围", "4.9 计算性能与方法消融",
    "4.10 工程启示与研究局限", "[待补证] 资源机制和强对照需由新增证据兑现",
    "写作任务：连接基准事实、策略比较、资源机制与决策边界",
])
overview["children"] = old_overview[:4] + [overview_four, rename(old_overview[7], "第5章 结论")] + old_overview[8:]

chapters = deepcopy(detail_root["children"])
c4, c5, c6, c7 = chapters[3:]
baseline = c4["children"]
mechanism = c5["children"]
discussion = c6["children"]
budget = rename(baseline[2], "4.3 经济预算—最低更新需求关系")
budget["children"].extend(deepcopy(mechanism[0]["children"]))
comparisons = rename(baseline[3], "4.4 同口径策略对照及文献联系")
comparisons["children"].extend(deepcopy(discussion[1]["children"]))
trajectories = rename(baseline[4], "4.5 调度特征与代价转移")
trajectories["children"].extend(deepcopy(discussion[2]["children"]))
engineering = node("4.10 工程启示与研究局限")
for source in [discussion[0], discussion[3], mechanism[4], discussion[4]]:
    engineering["children"].extend(deepcopy(source["children"]))
c4["title"] = "第4章 结果与讨论"
c4["children"] = [
    rename(baseline[0], "4.1 算例设置与数据"),
    rename(baseline[1], "4.2 最低更新需求的认证结果"), budget, comparisons, trajectories,
    rename(mechanism[1], "4.6 储氢对更新需求的替代作用"),
    rename(mechanism[2], "4.7 补氢能力与电网边界的反事实"),
    rename(mechanism[3], "4.8 敏感性与适用范围"),
    rename(baseline[5], "4.9 计算性能与方法消融"), engineering,
]
for sub in c4["children"]:
    seen = set()
    sub["children"] = [c for c in sub["children"] if not (c["title"] in seen or seen.add(c["title"]))]
detail_root["title"] = "五章正文：问题—方法—证据—边界"
detail_root["children"] = chapters[:3] + [c4, rename(c7, "第5章 结论")]
sheets[1]["title"] = "02 五章写作详纲"

replacements = {
    "落点：第3章方法、第4.2与4.6节": "落点：第3章方法、第4.2与4.9节",
    "落点：第5章核心结果、第6章解释": "落点：第4.3、4.6—4.8节结果，第4.10节解释",
    "落点：第5章机制主图": "落点：第4.6—4.7节机制主图",
    "对应图5：资源变化—需求区间联动": "对应图5：第4.6—4.7节资源变化—需求区间联动",
    "第5章机制保留待验证占位": "第4.6—4.8节机制与敏感性保留待验证占位",
    "本章是候选核心贡献，不能提前写成已发现规律": "资源机制是候选核心贡献，不能提前写成已发现规律",
    "综合第4、5章解释所得认识": "综合第4章各项结果解释所得认识",
    "[待补证] 最有潜力成为论文核心系统认识": "[待补证] 第4.6—4.7节形成核心系统认识",
}


def update(n):
    for a, b in replacements.items():
        n["title"] = n["title"].replace(a, b)
    for c in n["children"]:
        update(c)


for sheet in sheets:
    for root in sheet["roots"]:
        update(root)

navigation = sheets[2]["roots"][0]
navigation["children"].append(node("五章合并规则与内容去向", [
    "第1章引言、第2章模型、第3章方法保留独立篇章",
    "原基准结果、形成机制与讨论统一进入第4章",
    "预算结果与机制合并为4.3，避免重复绘制相同关系",
    "文献比较进入4.4，指标与代价转移进入4.5",
    "储氢、补氢和电网机制进入4.6—4.7",
    "敏感性进入4.8，计算消融进入4.9",
    "工程意义和局限综合在4.10，第5章只写结论",
    "完整扫描、额外分布和冗长消融转入SI",
]))
fig_six = next(c for c in navigation["children"] if c["title"] == "正文六幅建议图")
for c in fig_six["children"]:
    if c["title"].startswith("图6 "):
        c["children"].append(node("落点：第4.9节计算性能与消融"))

lines = []


def emit(n, depth):
    lines.append("  " * depth + "- " + n["title"])
    for child in n["children"]:
        emit(child, depth + 1)


for sheet in sheets:
    lines.append("# " + sheet["title"])
    for root in sheet["roots"]:
        emit(root, 0)
    lines.append("")
path.write_text("\n".join(lines), encoding="utf-8")
print("Reorganized to five chapters; old XMind retained in history")
