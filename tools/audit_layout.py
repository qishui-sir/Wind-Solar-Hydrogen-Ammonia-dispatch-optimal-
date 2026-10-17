#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""lower_bound_methods 05-21 目录整改自查。

只做静态文件检查：目录骨架、UTF-8 中文、报告必要字段、Markdown 相对链接、
VALIDATION 状态与证据哈希清单。绝不调用 MATLAB / Gurobi，也不做任何数值复算。

用法（在 project 根目录）:
    python tools/audit_layout.py
    python tools/audit_layout.py --root dsh_test/lower_bound_methods \
        --out dsh_test/lower_bound_methods/reports/audit_layout_20261017.json
    python tools/audit_layout.py --no-verify-hashes   # 只查清单结构，不重算 sha256

退出码: 0 = 无 error；1 = 存在 error；2 = 根目录不存在或参数错误。
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote

TARGET_DIRS = [f"{i:02d}_" for i in range(5, 22)]

METHOD_LEVEL_FILES = ["README.md", "reports/REPORT.md"]
RUN_LEVEL_FILES = [
    "reports/REPORT.md",
    "reports/VALIDATION.json",
    "reports/VALIDATION.md",
    "config/EVIDENCE_SHA256.json",
]
REPORT_SECTIONS = [
    ("方法", ("方法", "方法族")),
    ("模型域", ("模型域", "模型与域", "经济帽", "整数集")),
    ("执行与停止", ("真实执行", "停止原因", "执行")),
    ("状态与原始界", ("原始界字段", "objbound", "状态")),
    ("常数与guard", ("guard", "常数", "ceil")),
    ("数值与增量", ("403", "增量", "数值")),
    ("耗时", ("耗时", "墙钟", "solver")),
    ("证据SHA256", ("SHA256", "sha256", "哈希")),
    ("独立验收", ("独立验收", "独立签字", "待办")),
]
VALIDATION_REQUIRED = [
    "execution_status",
    "evidence_status",
    "independent_status",
    "adoption_status",
    "signer",
    "untested",
]
STATUS_ENUMS = {
    "execution_status": {"EXECUTED", "NOT_EXECUTED", "PARTIAL", "UNKNOWN"},
    "evidence_status": {"PRESENT", "PARTIAL", "MISSING", "UNKNOWN"},
    "independent_status": {"SIGNED", "NOT_SIGNED", "NOT_REVIEWED", "N/A", "UNKNOWN"},
    "adoption_status": {
        "ADOPTED", "SUPERSEDED", "NEGATIVE", "PREPARED", "NOT_ADOPTED",
        "RECORD_ONLY", "PREPARED_NOT_EXECUTED", "INFRA",
        "REPRODUCED_EXISTING_BOUND", "UNKNOWN",
    },
}
SKIP_RUN_DIRS = {"logs", "__pycache__", ".git"}
MINIMAL_METHOD = {"10_method_selection", "12_independent_acceptance", "17_even_interval_facets"}
LEGACY_REQUIRED = {"11_all_link_pricing", "14_cross29_pilot", "16_partition_certificate",
                   "15_weighted_count", "18_support_reprice", "19_local_ael_integer",
                   "20_two_price", "21_live_partition"}


def read_utf8(path: Path, errors: list, rel: str) -> str | None:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        errors.append({"code": "READ_ERROR", "path": rel, "detail": str(exc)})
        return None
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        errors.append({"code": "NOT_UTF8", "path": rel, "detail": str(exc)})
        return None


def chinese_ratio(text: str) -> float:
    cjk = len(re.findall(r"[\u4e00-\u9fff]", text))
    return cjk / max(1, len(text))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def is_run_tag(path: Path) -> bool:
    if not path.is_dir() or path.name in SKIP_RUN_DIRS or path.name.startswith(("_", ".")):
        return False
    return True


def check_md_links(path: Path, text: str, root: Path, warnings: list, rel: str) -> int:
    checked = 0
    for m in re.finditer(r"\[[^\]]*\]\(([^)]+)\)", text):
        target = m.group(1).strip().split("#")[0].strip()
        if not target or re.match(r"^[a-z]+:", target, re.I):
            continue
        target = unquote(target).replace("\\", "/")
        if target.startswith("/"):
            resolved = root / target.lstrip("/")
        else:
            resolved = (path.parent / target).resolve()
        checked += 1
        if not resolved.exists():
            warnings.append({
                "code": "BROKEN_LINK", "path": rel,
                "detail": f"链接目标不存在: {target}",
            })
    return checked


def check_report(path: Path, rel: str, errors: list, warnings: list, root: Path,
                 minimal: bool = False) -> dict:
    text = read_utf8(path, errors, rel)
    if text is None:
        return {}
    ratio = chinese_ratio(text)
    links = check_md_links(path, text, root, warnings, rel)
    if minimal:
        if len(re.findall(r"[\u4e00-\u9fff]", text)) < 100 or ratio < 0.08:
            warnings.append({"code": "LOW_CHINESE", "path": rel,
                             "detail": f"中文字符占比过低: {ratio:.3f}"})
        if "文档齐全绝非数值PASS" not in text and "文档齐全≠数值PASS" not in text:
            warnings.append({"code": "NO_DOC_VS_NUMERIC_DISCLAIMER", "path": rel,
                             "detail": "缺少「文档齐全≠数值PASS」声明"})
        if not any(k in text for k in ("没有数值", "无数值", "RECORD_ONLY",
                                        "PREPARED_NOT_EXECUTED", "RECORD（")):
            warnings.append({"code": "MINIMAL_NO_STATUS", "path": rel,
                             "detail": "记录/准备目录未明确“无 run/无数值”"})
        return {"chars": len(text), "chinese_ratio": round(ratio, 4),
                "links_checked": links, "minimal": True}
    if len(re.findall(r"[\u4e00-\u9fff]", text)) < 200 or ratio < 0.10:
        warnings.append({"code": "LOW_CHINESE", "path": rel,
                         "detail": f"中文字符占比过低: {ratio:.3f}"})
    missing = [name for name, keys in REPORT_SECTIONS
               if not any(k in text for k in keys)]
    # 「状态」与「执行」可以合写，但必须至少出现原始界字段关键字
    if "objbound" not in text and "原始界" not in text:
        missing.append("原始界字段")
    if missing:
        errors.append({"code": "MISSING_SECTION", "path": rel,
                       "detail": "报告缺少字段: " + "、".join(sorted(set(missing)))})
    if "文档齐全绝非数值PASS" not in text and "文档齐全≠数值PASS" not in text:
        warnings.append({"code": "NO_DOC_VS_NUMERIC_DISCLAIMER", "path": rel,
                         "detail": "缺少「文档齐全≠数值PASS」声明"})
    if re.search(r"数值\s*(结论)?\s*PASS|数值通过", text) and "绝非数值PASS" not in text:
        errors.append({"code": "UNSUPPORTED_NUMERIC_PASS", "path": rel,
                       "detail": "出现数值 PASS 表述但未声明独立验收"})
    return {"chars": len(text), "chinese_ratio": round(ratio, 4), "links_checked": links}


def check_readme(path: Path, rel: str, errors: list, warnings: list, root: Path) -> dict:
    """README 是 5 字段入口，不要求 run 报告的完整数值字段。"""
    text = read_utf8(path, errors, rel)
    if text is None:
        return {}
    ratio = chinese_ratio(text)
    if ratio < 0.05:
        warnings.append({"code": "LOW_CHINESE", "path": rel,
                         "detail": f"README 中文占比过低: {ratio:.3f}"})
    for key in ("方法", "状态", "结论数字", "权威报告", "未完成"):
        if key not in text:
            warnings.append({"code": "README_FIELD_MISSING", "path": rel, "detail": f"缺字段 {key}"})
    links = check_md_links(path, text, root, warnings, rel)
    if re.search(r"数值\s*(结论)?\s*PASS", text):
        errors.append({"code": "UNSUPPORTED_NUMERIC_PASS", "path": rel,
                       "detail": "README 出现数值 PASS 表述"})
    return {"chars": len(text), "chinese_ratio": round(ratio, 4), "links_checked": links,
            "kind": "readme"}


def check_method_report(path: Path, rel: str, errors: list, warnings: list, root: Path) -> dict:
    """方法级 REPORT.md 只查入口/状态/链接/免责声明，不要求 run 级数值字段。"""
    text = read_utf8(path, errors, rel)
    if text is None:
        return {}
    ratio = chinese_ratio(text)
    if len(re.findall(r"[\u4e00-\u9fff]", text)) < 100 or ratio < 0.08:
        warnings.append({"code": "LOW_CHINESE", "path": rel,
                         "detail": f"方法级报告中文字符占比过低: {ratio:.3f}"})
    links = check_md_links(path, text, root, warnings, rel)
    required = ("方法", "状态", "403", "独立验收")
    missing = [k for k in required if k not in text]
    if missing:
        warnings.append({"code": "METHOD_REPORT_FIELD_MISSING", "path": rel,
                         "detail": "方法级入口缺: " + "、".join(missing)})
    if "文档齐全绝非数值PASS" not in text and "文档齐全≠数值PASS" not in text:
        warnings.append({"code": "NO_DOC_VS_NUMERIC_DISCLAIMER", "path": rel,
                         "detail": "缺少「文档齐全≠数值PASS」声明"})
    if re.search(r"数值\s*(结论)?\s*PASS", text) and "绝非数值PASS" not in text:
        errors.append({"code": "UNSUPPORTED_NUMERIC_PASS", "path": rel,
                       "detail": "方法级报告出现未设限的数值 PASS"})
    return {"chars": len(text), "chinese_ratio": round(ratio, 4), "links_checked": links,
            "kind": "method_report"}


def check_validation(path: Path, rel: str, errors: list, warnings: list) -> dict:
    text = read_utf8(path, errors, rel)
    if text is None:
        return {}
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        errors.append({"code": "BAD_JSON", "path": rel, "detail": str(exc)})
        return {}
    missing = [k for k in VALIDATION_REQUIRED if k not in data]
    if missing:
        errors.append({"code": "VALIDATION_MISSING_FIELD", "path": rel,
                       "detail": "缺字段: " + "、".join(missing)})
    for key, allowed in STATUS_ENUMS.items():
        val = data.get(key)
        if val is not None and val not in allowed:
            errors.append({"code": "BAD_STATUS_ENUM", "path": rel,
                           "detail": f"{key}={val!r} 不在 {sorted(allowed)}"})
    if data.get("adoption_status") == "ADOPTED" and data.get("independent_status") != "SIGNED":
        errors.append({"code": "ADOPTED_WITHOUT_INDEPENDENT", "path": rel,
                       "detail": "ADOPTED 但 independent_status 不是 SIGNED"})
    if "不是数值验收" not in json.dumps(data, ensure_ascii=False) and \
       "非数值" not in json.dumps(data, ensure_ascii=False) and \
       "不签" not in json.dumps(data, ensure_ascii=False):
        warnings.append({"code": "SIGNER_AMBIGUOUS", "path": rel,
                         "detail": "signer 未说明仅是文档签字"})
    return {"keys": sorted(data.keys())}


def check_manifest(path: Path, rel: str, errors: list, warnings: list,
                   verify_hashes: bool) -> dict:
    text = read_utf8(path, errors, rel)
    if text is None:
        return {}
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        errors.append({"code": "BAD_JSON", "path": rel, "detail": str(exc)})
        return {}
    files = data.get("files")
    if not isinstance(files, list):
        errors.append({"code": "MANIFEST_NO_FILES", "path": rel, "detail": "files 不是数组"})
        return {}
    base = path.parent.parent
    checked = bad = 0
    for item in files:
        p = item.get("path") if isinstance(item, dict) else None
        if not p:
            errors.append({"code": "MANIFEST_ITEM_NO_PATH", "path": rel, "detail": str(item)[:120]})
            continue
        fpath = base / p
        if not fpath.exists():
            errors.append({"code": "MANIFEST_FILE_MISSING", "path": rel, "detail": p})
            continue
        if verify_hashes:
            checked += 1
            actual = sha256_file(fpath)
            if actual != item.get("sha256"):
                bad += 1
                errors.append({"code": "HASH_MISMATCH", "path": rel,
                               "detail": f"{p}: manifest={item.get('sha256')} actual={actual}"})
    return {"entries": len(files), "hash_checked": checked, "hash_bad": bad}


def audit_dir(root: Path, name: str, verify_hashes: bool) -> dict:
    d = root / name
    errors: list = []
    warnings: list = []
    result = {"dir": name, "exists": d.exists(), "runs": 0, "errors": errors,
              "warnings": warnings, "run_tags": []}
    if not d.exists():
        errors.append({"code": "DIR_MISSING", "path": name, "detail": "目录不存在"})
        return result
    for rel in METHOD_LEVEL_FILES:
        p = d / rel
        if not p.exists():
            errors.append({"code": "MISSING_FILE", "path": f"{name}/{rel}", "detail": "方法级规范入口缺失"})
        elif rel == "README.md":
            check_readme(p, f"{name}/{rel}", errors, warnings, root)
        elif rel == "reports/REPORT.md":
            if name in MINIMAL_METHOD:
                check_report(p, f"{name}/{rel}", errors, warnings, root, minimal=True)
            else:
                check_method_report(p, f"{name}/{rel}", errors, warnings, root)
    tests = d / "tests"
    if not tests.is_dir():
        errors.append({"code": "MISSING_DIR", "path": f"{name}/tests", "detail": "缺 tests 骨架"})
    else:
        test_files = [p for p in tests.rglob("*") if p.is_file()
                      and p.suffix.lower() in {".m", ".py", ".md"}]
        if not test_files:
            warnings.append({"code": "EMPTY_TESTS", "path": f"{name}/tests",
                             "detail": "tests 目录为空"})
        readme_t = tests / "README.md"
        if readme_t.exists():
            t = read_utf8(readme_t, errors, f"{name}/tests/README.md") or ""
            if not any(k in t for k in ("尚无可执行测试", "可执行测试", "测试入口")):
                warnings.append({"code": "TEST_NOTE_WEAK", "path": f"{name}/tests/README.md",
                                 "detail": "未说明可执行测试或尚无可执行测试"})
    runs = d / "runs"
    if not runs.is_dir():
        errors.append({"code": "MISSING_DIR", "path": f"{name}/runs", "detail": "缺 runs 骨架"})
        return result
    ledger = runs / "_TAG_LEDGER.md"
    ltext = ""
    if not ledger.exists():
        errors.append({"code": "MISSING_LEDGER", "path": f"{name}/runs/_TAG_LEDGER.md",
                       "detail": "缺 _TAG_LEDGER.md"})
    else:
        ltext = read_utf8(ledger, errors, f"{name}/runs/_TAG_LEDGER.md") or ""
        if "判定" not in ltext:
            warnings.append({"code": "LEDGER_NO_JUDGMENT", "path": f"{name}/runs/_TAG_LEDGER.md",
                             "detail": "台账无判定列"})
        lw: list = []
        check_md_links(ledger, ltext, root, lw, f"{name}/runs/_TAG_LEDGER.md")
        for w in lw:
            errors.append({"code": "LEDGER_BROKEN_LINK",
                           "path": f"{name}/runs/_TAG_LEDGER.md",
                           "detail": w.get("detail", "")})
    ext_path = runs / "_EXTERNAL_TAGS.md"
    external = []
    if ext_path.exists():
        etext = read_utf8(ext_path, errors, f"{name}/runs/_EXTERNAL_TAGS.md") or ""
        external = re.findall(r"^-\s+`([^`]+)`", etext, re.M)
    for tag in sorted(p for p in runs.iterdir() if is_run_tag(p)):
        if any(fnmatch.fnmatch(tag.name, pat) for pat in external):
            result["run_tags"].append({"tag": tag.name, "external": True, "miss": []})
            warnings.append({"code": "EXTERNAL_TAG_SKIPPED",
                             "path": f"{name}/runs/{tag.name}",
                             "detail": "外部 worker 正在写入；按 _EXTERNAL_TAGS.md 跳过，不判缺口"})
            continue
        result["runs"] += 1
        tag_rel = f"{name}/runs/{tag.name}"
        info = {"tag": tag.name, "miss": [], "report": None}
        for rel in RUN_LEVEL_FILES:
            if not (tag / rel).exists():
                info["miss"].append(rel)
        if info["miss"] and not (tag / "reports/REPORT_CN.md").exists():
            errors.append({"code": "RUN_MISSING_FILE", "path": tag_rel,
                           "detail": "缺 " + "、".join(info["miss"])})
        report = tag / "reports/REPORT.md"
        alt = tag / "reports/REPORT_CN.md"
        # 整改补写的 REPORT_CN.md 优先；旧 REPORT.md 不覆盖、只查存在性
        chosen = alt if alt.exists() else (report if report.exists() else None)
        if chosen:
            info["report"] = str(chosen.relative_to(root)).replace("\\", "/")
            if (chosen.name == "REPORT_CN.md" and report.exists()
                    and "REPORT_CN" not in ltext):
                warnings.append({"code": "CN_NOT_REFERENCED", "path": f"{tag_rel}/reports/REPORT.md",
                                 "detail": "旧 REPORT.md/台账均未引用 REPORT_CN.md"})
            check_report(chosen, info["report"], errors, warnings, root,
                         minimal=(tag.name == "20261017_acceptance_catalog"))
        validation = tag / "reports/VALIDATION.json"
        if validation.exists():
            info["validation"] = check_validation(
                validation, f"{tag_rel}/reports/VALIDATION.json", errors, warnings)
        if (tag / "config/EVIDENCE_SHA256.json").exists():
            info["manifest"] = check_manifest(
                tag / "config/EVIDENCE_SHA256.json",
                f"{tag_rel}/config/EVIDENCE_SHA256.json",
                errors, warnings, verify_hashes)
        if not (tag / "logs").is_dir():
            warnings.append({"code": "NO_LOGS_DIR", "path": tag_rel,
                             "detail": "缺 logs/（空 run 也应保留目录）"})
        result["run_tags"].append(info)
    legacy = runs / "_LEGACY_LAYOUT.md"
    result["legacy_doc"] = legacy.exists()
    if name in LEGACY_REQUIRED and not legacy.exists():
        warnings.append({"code": "MISSING_LEGACY_DOC", "path": f"{name}/runs/_LEGACY_LAYOUT.md",
                         "detail": "该目录有历史平铺日志/指针，缺分类文档"})
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description="lower_bound_methods 05-21 目录整改自查（不调用求解器）")
    default_root = Path("dsh_test/lower_bound_methods")
    ap.add_argument("--root", default=str(default_root), help="lower_bound_methods 目录")
    ap.add_argument("--out", default=None, help="输出 JSON 路径")
    ap.add_argument("--no-verify-hashes", action="store_true", help="不重算 sha256")
    ap.add_argument("--scope", default="05-21", help="检查范围，默认 05-21")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    if not root.is_dir():
        print(f"[audit] root not found: {root}", file=sys.stderr)
        return 2
    verify_hashes = not args.no_verify_hashes
    names = [p.name for p in sorted(root.iterdir()) if p.is_dir()]
    if args.scope == "05-21":
        names = [n for n in names if any(n.startswith(t) for t in TARGET_DIRS)]

    dirs = [audit_dir(root, n, verify_hashes) for n in names]
    total_errors = sum(len(d["errors"]) for d in dirs)
    total_warnings = sum(len(d["warnings"]) for d in dirs)
    total_runs = sum(d["runs"] for d in dirs)
    report = {
        "schema": "lower_bound_methods.layout_audit.v1",
        "tool": "tools/audit_layout.py",
        "solver_invoked": False,
        "root": str(root),
        "scope": args.scope,
        "generated_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "verify_hashes": verify_hashes,
        "summary": {
            "dirs": len(dirs),
            "run_tags": total_runs,
            "errors": total_errors,
            "warnings": total_warnings,
            "ok": total_errors == 0,
        },
        "dirs": dirs,
    }
    out = Path(args.out) if args.out else root / "reports" / "audit_layout_20261017.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[audit] dirs={len(dirs)} runs={total_runs} errors={total_errors} "
          f"warnings={total_warnings} -> {out}")
    if total_errors:
        for d in dirs:
            for e in d["errors"][:8]:
                print(f"  ERROR {d['dir']}: {e['code']} {e.get('path','')} {e.get('detail','')}")
    return 0 if total_errors == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
