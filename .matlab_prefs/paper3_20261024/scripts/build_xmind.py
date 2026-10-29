"""将本目录审核后的中文层次内容打包为现代JSON/传统XML双格式XMind。"""
from pathlib import Path
from uuid import uuid5, NAMESPACE_URL
from collections import Counter
import hashlib
import json
import re
import textwrap
import zipfile
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

BASE = Path(__file__).resolve().parents[1]
PROJECT = BASE.parents[2]
SOURCE = PROJECT / "paper/03_论文初稿框架与贡献定位.md"
OUTLINE = BASE / "脑图内容源稿.md"
DEST = BASE / "paper3_论文框架与证据路线_详细脑图.xmind"
PALETTE = ["#157F83", "#285CA6", "#6B59A5", "#AA6C25", "#3F7F55", "#97647B", "#54798A", "#9A7041", "#506A8E", "#6E7D47"]


def uid(value):
    return uuid5(NAMESPACE_URL, "paper3-mindmap-20261024/" + value).hex


def style(kind, properties, key):
    return {"id": uid("style/" + key), "type": kind, "properties": properties}


def children(topic):
    return topic.get("children", {}).get("attached", [])


def walk(topic, depth=1):
    yield topic, depth
    for child in children(topic):
        yield from walk(child, depth + 1)


def status(topic, inherited=""):
    title = topic["title"]
    if re.match(r"\[(已有证据|已有记录|已有轨迹|可绘制)\]", title):
        return "existing"
    if title.startswith("[待补证]"):
        return "pending"
    if title.startswith("[限制]"):
        return "boundary"
    return inherited


sheets = []
stack = []
for lineno, line in enumerate(OUTLINE.read_text(encoding="utf-8").splitlines(), 1):
    if not line.strip():
        continue
    if line.startswith("# "):
        sheet_title = line[2:].strip()
        sheet = {"id": uid("sheet/" + sheet_title), "class": "sheet", "title": sheet_title,
                 "topicPositioning": "free", "topicOverlapping": "none", "relationships": []}
        sheets.append(sheet)
        stack = []
        continue
    match = re.fullmatch(r"( *)- (.+)", line)
    assert match and len(match[1]) % 2 == 0, (lineno, line)
    depth = len(match[1]) // 2
    assert depth <= len(stack), ("skipped level", lineno)
    stack = stack[:depth]
    topic = {"id": uid(f"{sheet_title}/{lineno}/{match[2]}"), "class": "topic", "title": match[2]}
    if depth == 0:
        assert "rootTopic" not in sheet
        sheet["rootTopic"] = topic
    else:
        stack[-1].setdefault("children", {}).setdefault("attached", []).append(topic)
    stack.append(topic)

source_note = (
    "主体内容依据《03_论文初稿框架与贡献定位.md》，初稿日期2026-10-17，2026-10-24依作者要求改为五章。"
    "本脑图同步更新为五章，没有新增MILP求解。绿色表示已有证据，橙色表示待补证，红色表示限制。"
    "阶段区间[406,487]与正式较强证据[408,487]分开保留。"
    "图1—图6沿用paper3建议编号，不等同paper4成图编号。"
    "XMind云端插件的指南与身份接口均返回Unknown tool，未创建云端文件；此文件为本地原生XMind。"
)

for sheet_index, sheet in enumerate(sheets):
    root = sheet["rootTopic"]
    root["structureClass"] = "org.xmind.ui.map.unbalanced" if sheet_index == 0 else "org.xmind.ui.logic.right"
    root["notes"] = {"plain": {"content": source_note}}
    root["style"] = style("topic", {"svg:fill": "#18384B", "fo:color": "#FFFFFF", "fo:font-weight": "bold",
                                         "fo:font-family": "Microsoft YaHei", "fo:font-size": "20pt",
                                         "shape-class": "org.xmind.topicShape.roundedRect"}, root["id"])
    sheet["theme"] = {
        "id": uid("theme/" + sheet["id"]), "title": "论文研究框架",
        "centralTopic": root["style"],
        "mainTopic": style("topic", {"fo:font-family": "Microsoft YaHei", "fo:font-size": "14pt", "fo:font-weight": "bold"}, sheet["id"] + "/main"),
        "subTopic": style("topic", {"fo:font-family": "Microsoft YaHei", "fo:font-size": "11pt", "fo:color": "#263746"}, sheet["id"] + "/sub"),
        "map": style("map", {"svg:fill": "#FFFFFF"}, sheet["id"] + "/map"),
    }
    for bi, branch in enumerate(children(root)):
        color = PALETTE[bi % len(PALETTE)]
        for topic, relative_depth in walk(branch):
            props = {"fo:font-family": "Microsoft YaHei", "fo:color": "#263746", "line-color": color}
            if relative_depth == 1:
                props.update({"svg:fill": color, "fo:color": "#FFFFFF", "fo:font-weight": "bold", "fo:font-size": "14pt",
                              "shape-class": "org.xmind.topicShape.roundedRect"})
            else:
                props.update({"fo:font-size": "11pt", "svg:fill": "#F6F9FC"})
            st = status(topic)
            if st:
                colors = {"existing": ("#E8F3ED", "#236140", "flag-green"),
                          "pending": ("#FFF2D9", "#88521B", "flag-orange"),
                          "boundary": ("#FBECEE", "#9C3E48", "symbol-attention")}
                fill, text, marker = colors[st]
                props.update({"svg:fill": fill, "fo:color": text})
                topic["markers"] = [{"markerId": marker, "groupId": "flag" if marker.startswith("flag-") else "symbol"}]
            topic["style"] = style("topic", props, topic["id"])
            if sheet_index > 0 and relative_depth == 2 and children(topic):
                topic["branch"] = "folded"

# 只对需要解释来源的节点加备注，避免把可读标题藏入备注。
for sheet in sheets:
    for topic, depth in walk(sheet["rootTopic"]):
        title = topic["title"]
        if title.startswith("Zhou 2024"):
            topic["href"] = "https://www.sciencedirect.com/science/article/pii/S0196890424006617"
        elif title.startswith("Pistolesi 2026"):
            topic["href"] = "https://www.sciencedirect.com/science/article/pii/S0360319926019191"
        elif title.startswith("Fahr 2026"):
            topic["href"] = "https://juser.fz-juelich.de/record/1059387?ln=en"
        elif title.startswith("证据性质与本地锚点"):
            topic["notes"] = {"plain": {"content": "项目相对路径：dsh_test/lower_bound_methods/21_live_partition/integration/main_application_20261017/。这是paper3引用的既有运行记录，本次未重跑其求解。"}}
        elif "[406,487]" in title:
            topic["notes"] = {"plain": {"content": "用户阶段保守口径。不得无说明地与较强正式证据[408,487]交替使用。"}}
        elif "[408,487]" in title:
            topic["notes"] = {"plain": {"content": "paper3引用的较强正式记录。原模型可行上界487，安全连续界407.6472776682899保护取整为408。当前不是唯一最优点。"}}

# 现代结构校验与统计。
ids = [topic["id"] for sheet in sheets for topic, _ in walk(sheet["rootTopic"])]
assert len(ids) == len(set(ids))
chapter_titles = [t["title"] for t in children(sheets[1]["rootTopic"])]
assert len(chapter_titles) == 5
assert all(chapter_titles[i].startswith(f"第{i+1}章") for i in range(5))
stats = [{"sheet": sheet["title"], "topics": sum(1 for _ in walk(sheet["rootTopic"])),
          "depth": max(d for _, d in walk(sheet["rootTopic"])), "main_branches": len(children(sheet["rootTopic"]))} for sheet in sheets]

# 传统XML格式与现代JSON保持同一树和同一ID，兼容支持传统格式的阅读器。
CNS = "urn:xmind:xmap:xmlns:content:2.0"
SNS = "urn:xmind:xmap:xmlns:style:2.0"
MNS = "urn:xmind:xmap:xmlns:manifest:1.0"
XNS = "http://www.w3.org/1999/xlink"
ET.register_namespace("", CNS)
ET.register_namespace("xlink", XNS)
content_xml = ET.Element(f"{{{CNS}}}xmap-content", {"version": "2.0"})
styles_xml = ET.Element(f"{{{SNS}}}xmap-styles", {"version": "2.0"})
styles_bucket = ET.SubElement(styles_xml, f"{{{SNS}}}styles")
style_items = {}


def xml_topic(parent, topic):
    attrs = {"id": topic["id"], "style-id": topic["style"]["id"]}
    for key in ["structureClass", "branch"]:
        if key in topic:
            attrs["structure-class" if key == "structureClass" else key] = topic[key]
    if "href" in topic:
        attrs[f"{{{XNS}}}href"] = topic["href"]
    elem = ET.SubElement(parent, f"{{{CNS}}}topic", attrs)
    ET.SubElement(elem, f"{{{CNS}}}title").text = topic["title"]
    if "notes" in topic:
        n = ET.SubElement(elem, f"{{{CNS}}}notes")
        ET.SubElement(n, f"{{{CNS}}}plain").text = topic["notes"]["plain"]["content"]
    if topic.get("markers"):
        refs = ET.SubElement(elem, f"{{{CNS}}}marker-refs")
        for marker in topic["markers"]:
            ET.SubElement(refs, f"{{{CNS}}}marker-ref", {"marker-id": marker["markerId"]})
    style_items[topic["style"]["id"]] = topic["style"]
    if children(topic):
        wrapper = ET.SubElement(elem, f"{{{CNS}}}children")
        attached = ET.SubElement(wrapper, f"{{{CNS}}}topics", {"type": "attached"})
        for child in children(topic):
            xml_topic(attached, child)


for sheet in sheets:
    elem = ET.SubElement(content_xml, f"{{{CNS}}}sheet", {"id": sheet["id"]})
    ET.SubElement(elem, f"{{{CNS}}}title").text = sheet["title"]
    xml_topic(elem, sheet["rootTopic"])
for item in style_items.values():
    elem = ET.SubElement(styles_bucket, f"{{{SNS}}}style", {"id": item["id"], "type": "topic"})
    # 传统XML中的属性带命名空间，不能把冒号直接写入未声明的XML属性。
    props = {}
    for k, v in item["properties"].items():
        if k.startswith("fo:"):
            k = "{http://www.w3.org/1999/XSL/Format}" + k[3:]
        elif k.startswith("svg:"):
            k = "{http://www.w3.org/2000/svg}" + k[4:]
        props[k] = v
    ET.SubElement(elem, f"{{{SNS}}}topic-properties", props)

# 封面缩略图仅作索引预览，正文细节保留在可编辑节点中。
preview = Image.new("RGB", (1600, 1000), "#F4F7FA")
draw = ImageDraw.Draw(preview)
font_path = Path("C:/Windows/Fonts/msyh.ttc")
font = lambda size: ImageFont.truetype(str(font_path), size)
draw.text((60, 30), "paper3｜论文框架与证据路线", fill="#18384B", font=font(35))
draw.text((60, 84), "五章结构 · 公式与区间 · 图表与补证 · 2026-10-24", fill="#637889", font=font(21))
cards = [(60, 190, "研究主线", "固定装置＋同等年产量\n经济预算内最低更新需求"),
         (60, 460, "第1章 引言", "应用问题与文献定位\n贡献、证据与适用范围"),
         (60, 730, "第2章 模型", "AEL—储氢—HB及电网\n设定值、跟踪带与循环边"),
         (1130, 190, "第3章 认证方法", "严格与宽松双帽\n原域见证＋分区下界"),
         (1130, 460, "第4章 结果与讨论", "基准与强对照、资源机制\n敏感性、计算性能与局限"),
         (1130, 730, "第5章 结论", "可信范围、经济代价\n仅总结已验证结果")]
rootbox = (565, 405, 1035, 590)
for i, (x, y, title, body) in enumerate(cards):
    color = PALETTE[i]
    end = (x + 410, y + 75) if x < 800 else (x, y + 75)
    start = (565, 500) if x < 800 else (1035, 500)
    draw.line([start, end], fill=color, width=3)
    draw.rounded_rectangle((x, y, x + 410, y + 155), radius=16, fill="white", outline=color, width=2)
    draw.text((x + 22, y + 15), title, fill=color, font=font(25))
    draw.multiline_text((x + 22, y + 58), body, fill="#334A5B", font=font(20), spacing=10)
draw.rounded_rectangle(rootbox, radius=22, fill="#18384B")
draw.multiline_text((602, 435), "最低设定值更新需求\n经济预算＋年度调度\n已有证据 / 待补证 / 限制", fill="white", font=font(26), spacing=12)
preview_path = BASE / "论文脑图总览.png"
preview.save(preview_path)

payloads = {
    "content.json": json.dumps(sheets, ensure_ascii=False, indent=2).encode("utf-8"),
    "metadata.json": json.dumps({"creator": {"name": "Codex", "version": "1.0"}, "activeSheetId": sheets[0]["id"]}, ensure_ascii=False).encode("utf-8"),
    "content.xml": ET.tostring(content_xml, encoding="utf-8", xml_declaration=True),
    "styles.xml": ET.tostring(styles_xml, encoding="utf-8", xml_declaration=True),
    "Thumbnails/thumbnail.png": preview_path.read_bytes(),
    "resources/paper3_original.md": SOURCE.read_bytes(),
    "resources/outline.md": OUTLINE.read_bytes(),
}
manifest_entries = {key: {} for key in list(payloads) + ["manifest.json", "META-INF/manifest.xml"]}
payloads["manifest.json"] = json.dumps({"file-entries": manifest_entries}, ensure_ascii=False).encode("utf-8")
manifest_xml = ET.Element(f"{{{MNS}}}manifest")
for entry in manifest_entries:
    ET.SubElement(manifest_xml, f"{{{MNS}}}file-entry", {"full-path": entry})
payloads["META-INF/manifest.xml"] = ET.tostring(manifest_xml, encoding="utf-8", xml_declaration=True)
with zipfile.ZipFile(DEST, "w", compression=zipfile.ZIP_STORED) as archive:
    for name, data in payloads.items():
        archive.writestr(name, data)

with zipfile.ZipFile(DEST) as archive:
    assert archive.testzip() is None
    actual = json.loads(archive.read("content.json"))
    xml_actual = ET.fromstring(archive.read("content.xml"))
    xml_count = len(xml_actual.findall(f".//{{{CNS}}}topic"))
    assert xml_count == len(ids)
    assert actual == sheets
    assert all(name in archive.namelist() for name in manifest_entries)
    all_titles = "\n".join(topic["title"] for sheet in sheets for topic, _ in walk(sheet["rootTopic"]))
    for required in ["[406,487]", "[408,487]", "407.6472776682899", "31786951.3844", "662.706", "281.808", "23.059", "8761", "0.005", "40000"]:
        assert required in all_titles, required
    assert "\ufffd" not in all_titles
    topic_statuses = Counter(status(topic) or "plain" for sheet in sheets for topic, _ in walk(sheet["rootTopic"]))
result = {
    "passed_structure_checks": True, "created_at_local": "2026-10-24", "chapter_count": 5, "sheets": stats,
    "total_topics": len(ids), "xml_topics": xml_count, "status_topics": dict(topic_statuses),
    "xmind_sha256": hashlib.sha256(DEST.read_bytes()).hexdigest(),
    "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    "outline_sha256": hashlib.sha256(OUTLINE.read_bytes()).hexdigest(),
    "plugin": {"cloud_created": False, "guide_error": "Unknown tool", "whoami_error": "Unknown tool"},
    "native_open_checked": False, "solver_calls": 0,
    "format_sources": ["https://github.com/xmindltd/xmind-sdk-js/blob/master/src/common/model.ts",
                       "https://github.com/xmindltd/xmind-viewer/blob/master/src/xmindLoader.ts"],
}
(BASE / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"path": str(DEST), "total_topics": len(ids), "sheets": stats, "bytes": DEST.stat().st_size}, ensure_ascii=False, indent=2))
