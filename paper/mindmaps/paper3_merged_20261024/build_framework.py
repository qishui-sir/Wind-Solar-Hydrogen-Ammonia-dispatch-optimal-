"""由同一源稿构建单表XMind，并与插件返回的节点层次核对；不调用优化器。"""
from pathlib import Path
from uuid import uuid5, NAMESPACE_URL
import hashlib
import json
import re
import zipfile
import xml.etree.ElementTree as ET

BASE = Path(__file__).resolve().parent
PROJECT = BASE.parents[2]
SOURCE = BASE / "统一框架源稿.md"
DEST = BASE / "paper3_五章统一详细框架.xmind"
RECORD = json.loads((BASE / "xmind_plugin_record.json").read_text(encoding="utf-8"))
ORIGINAL = PROJECT / "paper/mindmaps/paper3_20261024/paper3_论文框架与证据路线_详细脑图.xmind"


def uid(value):
    return uuid5(NAMESPACE_URL, "paper3-merged-20261024/" + value).hex


def children(topic):
    return topic.get("children", {}).get("attached", [])


def walk(topic, path=()):
    current = path + (topic["title"],)
    yield topic, current
    for child in children(topic):
        yield from walk(child, current)


def add_note(topic, text):
    plain = topic.setdefault("notes", {}).setdefault("plain", {})
    plain["content"] = (plain.get("content", "") + "\n" + text).strip()


# 云端锚点用于保证下载文件与插件版逐节点对应；概括批注不是正文树节点。
cloud_paths, stack = {}, []
for line in RECORD["markdown"].splitlines():
    match = re.match(r"^(#+) (.+?) <!--t:([^|>]+)(?:\|[^>]*)?-->", line)
    if not match:
        continue
    depth, title, topic_id = len(match[1]) - 1, match[2], match[3]
    stack = stack[:depth] + [title]
    cloud_paths[tuple(stack)] = topic_id

root, stack, relations = None, [], []
for line in SOURCE.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    if line.lstrip().startswith("> "):
        add_note(stack[-1], line.lstrip()[2:])
        continue
    match = re.fullmatch(r"(#{1,4}) (.+)", line)
    assert match, ("正文只允许根、章、节及三级标题；说明须放备注", line)
    depth, title = len(match[1]) - 1, match[2]
    marks = re.findall(r"\{([^{}]+)\}", title)
    title = re.sub(r"\s*\{[^{}]+\}", "", title).strip()
    assert depth <= len(stack), (depth, title)
    stack = stack[:depth]
    path = tuple(t["title"] for t in stack) + (title,)
    assert path in cloud_paths, ("云端缺少主题", path)
    topic = {"id": cloud_paths[path], "class": "topic", "title": title}
    if stack:
        stack[-1].setdefault("children", {}).setdefault("attached", []).append(topic)
    else:
        assert root is None
        root = topic
    for mark in marks:
        if mark.startswith("summary: "):
            add_note(topic, "概括：" + mark.split(": ", 1)[1])
        elif mark.startswith("relation: "):
            target, label = mark.split(": ", 1)[1].split(" | ", 1)
            relations.append((topic["id"], target, label))
        else:
            assert mark == "emphasis", mark
    stack.append(topic)

nodes = list(walk(root))
paths = {path for _, path in nodes}
assert paths == set(cloud_paths), "本地与云端层次不一致"
by_id = {t["id"]: t for t, _ in nodes}
by_title = {t["title"]: t for t, _ in nodes}
for attrs in RECORD["attributes"]:
    topic = by_id[attrs["topicId"]]
    for key in ("href", "labels"):
        if key in attrs:
            topic[key] = attrs[key]
    if "note" in attrs:
        assert attrs["note"] == topic.get("notes", {}).get("plain", {}).get("content", ""), "主题备注与云端属性不同"
    if attrs.get("markers"):
        topic["markers"] = [{"markerId": m} for m in attrs["markers"]]

root["structureClass"] = "org.xmind.ui.logic.right"
sheet = {"id": uid("sheet"), "class": "sheet", "title": "五章统一详细框架", "rootTopic": root,
         "topicPositioning": "free", "topicOverlapping": "none", "relationships": []}
for source_id, target_title, label in relations:
    sheet["relationships"].append({"id": uid(source_id + target_title), "title": label,
                                   "end1Id": source_id, "end2Id": by_title[target_title]["id"]})

# 可兼容传统阅读器的XML，所有主题与现代JSON使用相同ID、备注和链接。
CNS = "urn:xmind:xmap:xmlns:content:2.0"
XNS = "http://www.w3.org/1999/xlink"
MNS = "urn:xmind:xmap:xmlns:manifest:1.0"
ET.register_namespace("", CNS)
ET.register_namespace("xlink", XNS)
content = ET.Element(f"{{{CNS}}}xmap-content", {"version": "2.0"})
xml_sheet = ET.SubElement(content, f"{{{CNS}}}sheet", {"id": sheet["id"]})
ET.SubElement(xml_sheet, f"{{{CNS}}}title").text = sheet["title"]


def xml_topic(parent, topic):
    attrs = {"id": topic["id"]}
    if topic.get("structureClass"):
        attrs["structure-class"] = topic["structureClass"]
    if topic.get("branch"):
        attrs["branch"] = topic["branch"]
    if topic.get("href"):
        attrs[f"{{{XNS}}}href"] = topic["href"]
    element = ET.SubElement(parent, f"{{{CNS}}}topic", attrs)
    ET.SubElement(element, f"{{{CNS}}}title").text = topic["title"]
    if topic.get("notes"):
        note = ET.SubElement(element, f"{{{CNS}}}notes")
        ET.SubElement(note, f"{{{CNS}}}plain").text = topic["notes"]["plain"]["content"]
    if topic.get("labels"):
        labels = ET.SubElement(element, f"{{{CNS}}}labels")
        for text in topic["labels"]:
            ET.SubElement(labels, f"{{{CNS}}}label").text = text
    if topic.get("markers"):
        refs = ET.SubElement(element, f"{{{CNS}}}marker-refs")
        for marker in topic["markers"]:
            ET.SubElement(refs, f"{{{CNS}}}marker-ref", {"marker-id": marker["markerId"]})
    if children(topic):
        holder = ET.SubElement(element, f"{{{CNS}}}children")
        attached = ET.SubElement(holder, f"{{{CNS}}}topics", {"type": "attached"})
        for child in children(topic):
            xml_topic(attached, child)


xml_topic(xml_sheet, root)
if sheet["relationships"]:
    holder = ET.SubElement(xml_sheet, f"{{{CNS}}}relationships")
    for relation in sheet["relationships"]:
        element = ET.SubElement(holder, f"{{{CNS}}}relationship",
                                {"id": relation["id"], "end1": relation["end1Id"], "end2": relation["end2Id"]})
        ET.SubElement(element, f"{{{CNS}}}title").text = relation["title"]

input_paths = [ORIGINAL, PROJECT / "paper/03_论文初稿框架与贡献定位.md",
               PROJECT / "paper/05_第三章_经济阈值识别与上下界认证方法_初稿.md",
               PROJECT / "paper/06_第三章算法贡献评估与后续方案.md",
               PROJECT / "paper/07_与Zhou_S3的差异及论文贡献强化方案.md",
               PROJECT / "paper/08_统计误差解释与下界基准选择.md"]
inputs = [{"path": str(p.relative_to(PROJECT)), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
          for p in input_paths]
payloads = {"content.json": json.dumps([sheet], ensure_ascii=False, indent=2).encode("utf-8"),
            "metadata.json": json.dumps({"creator": {"name": "Codex", "version": "1.0"},
                                          "activeSheetId": sheet["id"]}).encode("utf-8"),
            "content.xml": ET.tostring(content, encoding="utf-8", xml_declaration=True),
            "resources/source_outline.md": SOURCE.read_bytes(),
            "resources/source_index.json": json.dumps(inputs, ensure_ascii=False, indent=2).encode("utf-8")}
entries = {name: {} for name in [*payloads, "manifest.json", "META-INF/manifest.xml"]}
payloads["manifest.json"] = json.dumps({"file-entries": entries}).encode("utf-8")
manifest = ET.Element(f"{{{MNS}}}manifest")
for name in entries:
    ET.SubElement(manifest, f"{{{MNS}}}file-entry", {"full-path": name})
payloads["META-INF/manifest.xml"] = ET.tostring(manifest, encoding="utf-8", xml_declaration=True)
with zipfile.ZipFile(DEST, "w", compression=zipfile.ZIP_STORED) as archive:
    for name, value in payloads.items():
        archive.writestr(name, value)

with zipfile.ZipFile(DEST) as archive:
    assert archive.testzip() is None
    assert json.loads(archive.read("content.json")) == [sheet]
    xml = ET.fromstring(archive.read("content.xml"))
    xml_nodes = xml.findall(f".//{{{CNS}}}topic")
    assert [t.attrib["id"] for t in xml_nodes] == [t["id"] for t, _ in nodes]
    assert [t.find(f"{{{CNS}}}title").text for t in xml_nodes] == [t["title"] for t, _ in nodes]
chapters = [t["title"] for t in children(root)]
assert len(chapters) == 5 and all(t.startswith(f"第{i}章") for i, t in enumerate(chapters, 1))
all_text = "\n".join(t["title"] + "\n" + t.get("notes", {}).get("plain", {}).get("content", "") for t, _ in nodes)
required = ["[408,487]", "≤407", "408—486", "407.6472776682899", "31786951.38443569",
            "31787614.09013145", "22.5363", "B0=Uref", "N(x)≤k", "8761", "0.005",
            "根LP获取价格后固定", "部分扫描结合", "全年度连续界", "不写成95%置信区间",
            "储氢", "可选", "待验证"]
assert all(text in all_text for text in required)
assert "\ufffd" not in all_text and len(by_id) == len(nodes)
assert len(nodes) == RECORD["contentHealth"]["topics"]
assert "406仅为历史保守口径" in all_text
for ci, chapter in enumerate(children(root), 1):
    assert children(chapter)
    for si, section in enumerate(children(chapter), 1):
        assert section["title"].startswith(f"{ci}.{si} "), section["title"]
        assert len(children(section)) >= 2
        for ti, third in enumerate(children(section), 1):
            assert third["title"].startswith(f"{ci}.{si}.{ti} "), third["title"]
            assert not children(third), "不应存在第四级标题"
            note = third.get("notes", {}).get("plain", {}).get("content", "")
            assert note and len(note.encode("utf-8")) <= 2048
            assert not any(x in third["title"] for x in ("投稿", "第一优先", "待验证", "已有：", "图1", "S1"))
chapter_counts = [{"chapter": ch["title"], "sections": len(children(ch)),
                   "third_level_headings": sum(len(children(sec)) for sec in children(ch))}
                  for ch in children(root)]
validation = {"passed_structure_checks": True, "cloud_outline_matches_local": True,
              "sheet_count": 1, "chapter_count": 5, "chapters": chapters, "total_topics": len(nodes),
              "max_depth_including_root": max(len(path) for _, path in nodes),
              "formal_heading_levels": 3, "numbering_hierarchy_passed": True,
              "chapter_counts": chapter_counts,
              "second_level_headings": sum(x["sections"] for x in chapter_counts),
              "third_level_headings": sum(x["third_level_headings"] for x in chapter_counts),
              "content_presentation": "三级标题以下仅有备注，无第四级或第五级标题",
              "relationship_count": len(relations), "marker_topics": sum(bool(t.get("markers")) for t, _ in nodes),
              "folded_sections": sum(t.get("branch") == "folded" for t, _ in nodes),
              "xmind_sha256": hashlib.sha256(DEST.read_bytes()).hexdigest(),
              "outline_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
              "semantic_review": RECORD.get("headingReview", {}), "input_sources": inputs,
              "plugin": {"cloud_created": True, "file_id": RECORD["fileId"], "url": RECORD["fileUrl"],
                         "read_back_verified": RECORD.get("cloudReadBackVerified", False),
                         "sheet_id": RECORD.get("cloudSheetId")},
              "native_desktop_open_verified": False, "solver_calls": 0}
(BASE / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"path": str(DEST), "sheets": 1, "topics": len(nodes), "chapters": chapters,
                  "bytes": DEST.stat().st_size}, ensure_ascii=False, indent=2))
