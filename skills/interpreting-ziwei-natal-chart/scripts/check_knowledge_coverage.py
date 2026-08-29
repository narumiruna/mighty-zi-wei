#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["hanzidentifier==1.3.0"]
# ///
"""檢查本命盤 Skill 的知識 schema、來源完整性、安全邊界與產品契約。"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import date, datetime
from html.parser import HTMLParser
from pathlib import Path
from hanzidentifier import is_traditional


SKILL_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = SKILL_ROOT.parents[1]
REFERENCES = SKILL_ROOT / "references"
SOURCES = REFERENCES / "sources"
MODERN_REFERENCE = REFERENCES / "modern-functional-language.md"
SOURCE_EVIDENCE = REFERENCES / "source-evidence.md"
SOURCE_MANIFEST = SOURCES / "manifest.json"
SEED_MATRIX = REFERENCES / "seed-support-matrix.md"
SEED_CONTRACT = REFERENCES / "seed-contract.json"
PRODUCT_BOUNDARIES = REFERENCES / "product-integration-boundaries.md"
GENERATE_SCRIPT = SKILL_ROOT / "scripts/generate_chart_facts.py"
SKILL_FILE = SKILL_ROOT / "SKILL.md"
RULESET = REPOSITORY_ROOT / "RULESET.md"

MAIN_STARS = (
    "ziWei", "tianJi", "taiYang", "wuQu", "tianTong", "lianZhen", "tianFu",
    "taiYin", "tanLang", "juMen", "tianXiang", "tianLiang", "qiSha", "poJun",
)
SUPPORTING_STARS = (
    "zuoFu", "youBi", "wenChang", "wenQu", "tianKui", "tianYue", "qingYang",
    "tuoLuo", "huoXing", "lingXing", "diKong", "diJie", "luCun", "tianMa",
)
PALACES = (
    "life", "siblings", "spouse", "children", "wealth", "health", "travel",
    "friends", "career", "property", "fortune", "parents",
)
BODY_PALACES = ("life", "spouse", "wealth", "travel", "career", "fortune")
TRANSFORMATIONS = ("lu", "quan", "ke", "ji")

MAIN_STAR_NAMES = dict(zip(MAIN_STARS, ("紫微", "天機", "太陽", "武曲", "天同", "廉貞", "天府", "太陰", "貪狼", "巨門", "天相", "天梁", "七殺", "破軍"), strict=True))
SUPPORTING_STAR_NAMES = dict(zip(SUPPORTING_STARS, ("左輔", "右弼", "文昌", "文曲", "天魁", "天鉞", "擎羊", "陀羅", "火星", "鈴星", "地空", "地劫", "祿存", "天馬"), strict=True))
PALACE_NAMES = dict(zip(PALACES, ("命宮", "兄弟宮", "夫妻宮", "子女宮", "財帛宮", "疾厄宮", "遷移宮", "僕役宮", "官祿宮", "田宅宮", "福德宮", "父母宮"), strict=True))
TRANSFORMATION_NAMES = dict(zip(TRANSFORMATIONS, ("化祿", "化權", "化科", "化忌"), strict=True))

DOMAIN_PATHS = {
    "Star": REPOSITORY_ROOT / "apps/ios/MightyZiWei/Domain/Star.swift",
    "PalaceKind": REPOSITORY_ROOT / "apps/ios/MightyZiWei/Domain/Palace.swift",
    "TransformationKind": REPOSITORY_ROOT / "apps/ios/MightyZiWei/Domain/Transformation.swift",
}
DANGEROUS_ASSERTIONS = re.compile(r"必然|注定|肯定會|終將|早逝|必離婚|必破產|一定會|必定會|保證")
CERTAINTY_MARKERS = re.compile(r"一定|必定|必然|注定|肯定|鐵定|遲早|終將|不會|必[有離破犯死病傷亡夭絕]")
HIGH_RISK_TOPICS = re.compile(r"犯罪|傾家蕩產|破產|貧窮|財富|收入|死亡|早逝|長壽|壽元|壽命|疾病|診斷|離婚|婚姻破裂|懷孕|流產|災禍|意外|受傷|暴力")
DESTINY_OUTCOMES = re.compile(r"此人|一生|終身|命中|難逃|斷定|判定|可知|陽壽|短促|窮困|潦倒|婚緣|破敗|善終|子嗣|無望|孤苦|帶殘|牢獄|之災|絕嗣|刑剋|夭折|富貴|貧賤|發財")
DIRECT_PERSON = re.compile(r"此人|你將|你會|當事人將|當事人會")
NEGATED_RISK = re.compile(r"不得|不能|不可|不表示|不等於|不是|不構成|不預測|不宣稱|避免")
SAFE_FRAMING = re.compile(r"可能|可以|可用|可表示|觀察|用來|只可|適合|傾向")
AUTHORED_SIMPLIFIED_OR_NON_TAIWAN = {"網絡": "網路", "几": "幾"}


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


@dataclass(frozen=True)
class ScoreItem:
    name: str
    maximum: int
    failures: tuple[str, ...]
    evidence: str

    @property
    def earned(self) -> int:
        return 0 if self.failures else self.maximum


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="驗證紫微斗數本命盤 Skill 的 100 分知識完整度。")
    parser.add_argument("--online", action="store_true", help="連線重查維基文庫 revision API 與關鍵外部頁面。")
    parser.add_argument("--self-test", action="store_true", help="執行 checker 反例測試。")
    return parser.parse_args()


def read_text(path: Path) -> str:
    if not path.is_file():
        raise FileNotFoundError(f"缺少檔案：{path.relative_to(REPOSITORY_ROOT)}")
    return path.read_text(encoding="utf-8")


def section(text: str, heading: str, level: int) -> str:
    prefix = "#" * level
    marker = f"{prefix} {heading}\n"
    start = text.find(marker)
    if start < 0:
        return ""
    body_start = start + len(marker)
    candidates = []
    for candidate_level in range(1, level + 1):
        position = text.find(f"\n{'#' * candidate_level} ", body_start)
        if position >= 0:
            candidates.append(position)
    return text[body_start : min(candidates) if candidates else len(text)]


def parse_fields(body: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in body.splitlines():
        match = re.match(r"^- ([^：]+)：(.+)$", line)
        if match:
            fields[match.group(1).strip()] = match.group(2).strip()
    return fields


def unsafe_claim_value(value: str) -> bool:
    if NEGATED_RISK.search(value):
        return False
    if DESTINY_OUTCOMES.search(value):
        return True
    if DIRECT_PERSON.search(value) and not value.endswith("？") and not re.search(r"可能|傾向|可以觀察", value):
        return True
    direct_risk = HIGH_RISK_TOPICS.search(value)
    return bool(DANGEROUS_ASSERTIONS.search(value) or direct_risk or (CERTAINTY_MARKERS.search(value) and HIGH_RISK_TOPICS.search(value)))


def check_authored_prose_safety(text: str) -> list[str]:
    failures: list[str] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        if unsafe_claim_value(line):
            failures.append(f"現代語句第 {line_number} 行含高風險宿命斷言")
    return failures


def check_claim_sections(
    text: str,
    names: dict[str, str],
    prefix: str,
    required_fields: tuple[str, ...],
    level: int,
) -> list[str]:
    failures: list[str] = []
    seen_ids: set[str] = set()
    for identifier, heading in names.items():
        body = section(text, heading, level)
        fields = parse_fields(body)
        expected_id = f"`{prefix}{identifier}`。"
        if fields.get("claim ID") != expected_id:
            failures.append(f"{identifier} claim ID 不正確")
        for field in required_fields:
            value = fields.get(field, "")
            if not value:
                failures.append(f"{identifier} 缺少 {field}")
            elif field != "不可推論" and unsafe_claim_value(value):
                failures.append(f"{identifier} 的 {field} 含宿命斷言")
            elif field not in ("不可推論", "可核對問題") and not SAFE_FRAMING.search(value):
                failures.append(f"{identifier} 的 {field} 缺少非宿命 framing")
        question = fields.get("可核對問題")
        if question and not question.endswith("？"):
            failures.append(f"{identifier} 的核對問題不是問句")
        claim_id = fields.get("claim ID", "")
        if claim_id in seen_ids:
            failures.append(f"重複 claim ID：{claim_id}")
        seen_ids.add(claim_id)
    return failures


def declared_swift_cases(path: Path, enum_name: str) -> tuple[str, ...]:
    text = read_text(path)
    marker = f"public enum {enum_name}"
    start = text.find(marker)
    if start < 0:
        return ()
    end = text.find("\npublic ", start + len(marker))
    block = text[start : end if end >= 0 else len(text)]
    cases: list[str] = []
    for match in re.finditer(r"^    case ([A-Za-z][A-Za-z0-9_, ]*)$", block, re.MULTILINE):
        cases.extend(value.strip() for value in match.group(1).split(","))
    return tuple(cases)


def check_local_links(paths: list[Path]) -> list[str]:
    failures: list[str] = []
    pattern = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
    for path in paths:
        for target in pattern.findall(read_text(path)):
            if "://" in target or target.startswith(("#", "mailto:")):
                continue
            local_target = target.split("#", 1)[0]
            if local_target and not (path.parent / local_target).resolve().exists():
                failures.append(f"{path.relative_to(REPOSITORY_ROOT)} -> {target}")
    return failures


def frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---\n") or "\n---\n" not in text:
        return {}
    raw = text.split("\n---\n", 1)[0].removeprefix("---\n")
    result: dict[str, str] = {}
    for line in raw.splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            result[key.strip()] = value.strip()
    return result


def body_sha256(text: str) -> str:
    body = text.split("\n---\n", 1)[1]
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def normalized_source_text(value: str) -> str:
    return re.sub(r"[^0-9A-Za-z\u3400-\u9fff]+", "", value)


def rendered_text(html_text: str) -> str:
    parser = TextExtractor()
    parser.feed(html_text)
    return html.unescape("".join(parser.parts))


def snapshot_coverage(snapshot: str, rendered: str) -> float:
    rendered_normalized = normalized_source_text(rendered)
    excluded_prefixes = ("#", "|", "```", "本檔案", "網頁表格", "原文可能", "引用時")
    candidates = []
    for line in snapshot.split("\n---\n", 1)[1].splitlines():
        normalized = normalized_source_text(line)
        if len(normalized) >= 4 and not line.startswith(excluded_prefixes):
            candidates.append(normalized)
    total = sum(len(value) for value in candidates)
    matched = sum(len(value) for value in candidates if value in rendered_normalized)
    return matched / total if total else 0.0


def valid_wikisource_url(value: str) -> bool:
    return value.startswith("https://zh.wikisource.org/")


def check_source_manifest(online: bool) -> list[str]:
    failures: list[str] = []
    manifest = json.loads(read_text(SOURCE_MANIFEST))
    if manifest.get("schemaVersion") != 1:
        failures.append("來源 manifest schemaVersion 不正確")
    anchors = manifest.get("snapshotAnchors", {})
    expected_headings = {
        "quanshu-volume-1-foundations.md": ("### 太微賦", "### 鬥數發微論"),
        "quanshu-volume-1-patterns.md": ("### 鬥數骨髓賦", "### 定富局"),
        "quanshu-volume-1-star-dialogues.md": ("#### 問紫微所主若何？", "#### 問破軍所主若何？"),
        "quanshu-volume-2-life-palace.md": ("### 一 命宮",),
        "quanshu-volume-2-palaces-2-3.md": ("### 二兄弟", "### 三妻妾"),
        "quanshu-volume-2-palaces-4-6.md": ("### 四子女", "### 六疾厄"),
        "quanshu-volume-2-palaces-7-12.md": ("### 七遷移", "### 十二父母"),
        "quanshu-volume-2-setup.md": ("### 安身命例",),
    }
    listed_files: set[str] = set()
    for volume in manifest.get("volumes", {}).values():
        revision_id = int(volume["revisionId"])
        revision_time = datetime.fromisoformat(volume["revisionTimestamp"].replace("Z", "+00:00"))
        retrieved_time = datetime.fromisoformat(volume["retrievedAt"])
        if retrieved_time.timestamp() < revision_time.timestamp():
            failures.append(f"revision {revision_id} 的擷取時間早於修訂建立時間")
        for filename, expected_hash in volume.get("snapshots", {}).items():
            listed_files.add(filename)
            path = SOURCES / filename
            text = read_text(path)
            metadata = frontmatter(text)
            if not valid_wikisource_url(metadata.get("source_url", "")):
                failures.append(f"{filename} 的 source_url 不是維基文庫 HTTPS 頁面")
            if not valid_wikisource_url(metadata.get("revision_url", "")):
                failures.append(f"{filename} 的 revision_url 不是維基文庫 HTTPS 頁面")
            if str(revision_id) not in metadata.get("revision_url", ""):
                failures.append(f"{filename} 的 revision_url 與 manifest 不同")
            if date.fromisoformat(metadata["retrieved_at"]) < revision_time.date():
                failures.append(f"{filename} 的 retrieved_at 早於修訂建立日期")
            if body_sha256(text) != expected_hash:
                failures.append(f"{filename} 內容 hash 不符")
            anchor = anchors.get(filename, "")
            if len(anchor) < 12 or anchor not in normalized_source_text(text):
                failures.append(f"{filename} 缺少來源衍生 anchor")
            if len(text.splitlines()) < 50:
                failures.append(f"{filename} 內容過短")
            for heading in expected_headings[filename]:
                if heading not in text:
                    failures.append(f"{filename} 缺少預期章節 {heading}")
        if online:
            request = urllib.request.Request(
                volume["revisionApiUrl"],
                headers={"User-Agent": "MightyZiWeiSkillVerifier/1.0 (source integrity check)"},
            )
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    data = json.load(response)
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
                failures.append(f"revision {revision_id} 線上查核失敗：{error}")
                continue
            revision = data["query"]["pages"][0]["revisions"][0]
            content = revision["slots"]["main"]["content"]
            if revision["revid"] != revision_id or revision["timestamp"] != volume["revisionTimestamp"]:
                failures.append(f"revision {revision_id} 線上 metadata 不符")
            if hashlib.sha256(content.encode("utf-8")).hexdigest() != volume["sourceContentSha256"]:
                failures.append(f"revision {revision_id} 線上內容 hash 不符")
            normalized_content = normalized_source_text(content)
            for filename in volume.get("snapshots", {}):
                if anchors.get(filename, "") not in normalized_content:
                    failures.append(f"{filename} 的來源 anchor 不在 revision {revision_id}")

            render_request = urllib.request.Request(
                volume["renderApiUrl"],
                headers={"User-Agent": "MightyZiWeiSkillVerifier/1.0 (snapshot derivation check)"},
            )
            try:
                with urllib.request.urlopen(render_request, timeout=30) as response:
                    render_data = json.load(response)
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
                failures.append(f"revision {revision_id} rendered 內容查核失敗：{error}")
                continue
            render_html = render_data["parse"]["text"]
            if hashlib.sha256(render_html.encode("utf-8")).hexdigest() != volume["renderedContentSha256"]:
                failures.append(f"revision {revision_id} rendered 內容 hash 不符")
            source_rendered_text = rendered_text(render_html)
            for filename in volume.get("snapshots", {}):
                coverage = snapshot_coverage(read_text(SOURCES / filename), source_rendered_text)
                if coverage < 0.60:
                    failures.append(f"{filename} 與 rendered revision 的文字覆蓋率過低：{coverage:.1%}")
    actual_files = {path.name for path in SOURCES.glob("*.md")}
    if listed_files != actual_files:
        failures.append("來源 manifest 的分檔清單不完整")
    return failures


def check_evidence_ledger(text: str, online: bool) -> list[str]:
    failures: list[str] = []
    for number in range(1, 9):
        marker = f"## E{number:02d} "
        start = text.find(marker)
        if start < 0:
            failures.append(f"缺少 E{number:02d}")
            continue
        end = text.find("\n## ", start + len(marker))
        block = text[start : end if end >= 0 else len(text)]
        if "可支持：" not in block or "不能支持：" not in block:
            failures.append(f"E{number:02d} 缺少支持邊界")
        if number not in (7, 8) and "https://" not in block:
            failures.append(f"E{number:02d} 缺少 HTTPS 識別")
    for marker in ("0470017", "rarecatx0428879", "unresolved", "unverified-school-difference"):
        if marker not in text:
            failures.append(f"證據帳缺少 {marker}")
    key_pages = (
        ("https://rbook.ncl.edu.tw/NCLSearch/Search/Index/2", "中文古籍聯合目錄"),
        ("https://ctext.org/wiki.pl?if=gb&res=979714", ""),
        ("https://play.google.com/store/books/details?id=JvAVBQAAQBAJ", "JvAVBQAAQBAJ"),
        ("https://search.worldcat.org/zh-tw/title/58994949", "58994949"),
    )
    for url, identifier in key_pages:
        if url not in text:
            failures.append(f"證據帳缺少固定外部頁面：{url}")
        elif online:
            result = subprocess.run(
                ["curl", "--fail", "--location", "--silent", "--show-error", "--user-agent", "MightyZiWeiSkillVerifier/1.0", url],
                capture_output=True,
                text=True,
                timeout=45,
            )
            if result.returncode != 0:
                failures.append(f"外部頁面查核失敗：{url}（{result.stderr.strip()}）")
            elif identifier and identifier not in result.stdout:
                failures.append(f"外部頁面缺少必要識別：{url} -> {identifier}")
    detail_urls = re.findall(r"https://rbook\.ncl\.edu\.tw/NCLSearch/Search/SearchDetail\?[^\s]+", text)
    if len(detail_urls) != 2:
        failures.append("E03 缺少兩筆固定詳細書目 URL")
    elif online:
        detail_content = ""
        for url in detail_urls:
            result = subprocess.run(
                ["curl", "--fail", "--location", "--silent", "--show-error", "--user-agent", "MightyZiWeiSkillVerifier/1.0", url],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode != 0:
                failures.append(f"E03 詳細頁查核失敗：{result.stderr.strip()}")
            detail_content += result.stdout
        for identifier in ("0470017", "rarecatx0428879"):
            if identifier not in detail_content:
                failures.append(f"E03 詳細頁未重現識別：{identifier}")
    if "example.invalid" in text:
        failures.append("證據帳含失效占位網域")
    return failures


def canonical_sha256(value: object) -> str:
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def check_seed_contract(skill: str, matrix: str, modern: str) -> list[str]:
    failures: list[str] = []
    required = (
        "seed-support-matrix.md", "seed ID", "原始 meaning", "全部 evidence fact IDs",
        "只列 facts 與不支援限制",
    )
    for marker in required:
        if marker not in skill:
            failures.append(f"SKILL.md 缺少 seed 契約：{marker}")
    matrix_markers = (
        "InterpretationSeedBuilder", "五個 baseline", "十四主星", "目前沒有 approved seed 的項目",
        "只有 fact ID 而沒有 seed ID", "factsComplete", "外部傳入資料",
    )
    for marker in matrix_markers:
        if marker not in matrix:
            failures.append(f"seed 支援矩陣缺少：{marker}")
    status_markers = (
        "每個 `modern.palace.*` claim 的整體狀態", "每個 `modern.body.*` claim 的狀態",
        "每個 `modern.star.*` 主星 claim 的整體狀態", "每個六吉、六煞、祿存與天馬 claim 的整體狀態",
        "每個 `modern.transformation.*` claim 的狀態", "資源、拉力與牽制等解讀語句狀態",
    )
    for marker in status_markers:
        if marker not in modern:
            failures.append(f"現代語句缺少逐組 claim 狀態：{marker}")

    contract = json.loads(read_text(SEED_CONTRACT))
    builder_path = REPOSITORY_ROOT / contract["builderPath"]
    if hashlib.sha256(builder_path.read_bytes()).hexdigest() != contract["builderSourceSha256"]:
        failures.append("InterpretationSeedBuilder 與 seed contract hash 不符")
    if set(contract["mainStarIDs"]) != set(MAIN_STARS) or contract["expectedSeedCount"] != 19:
        failures.append("seed contract 的主星集合或 seed 數量不正確")
    expected_categories = {"overview", "personality", "career", "wealth", "relationships"}
    main_meanings = contract.get("mainStarMeanings", {})
    if set(main_meanings) != set(MAIN_STARS) or any(set(values) != expected_categories for values in main_meanings.values()):
        failures.append("seed contract 沒有完整 14 × 5 主星 meanings")
    else:
        for star_id, values in main_meanings.items():
            for category, meaning in values.items():
                if not meaning.strip() or not is_traditional(meaning) or unsafe_claim_value(meaning):
                    failures.append(f"seed contract meaning 不安全：{star_id}.{category}")

    result = subprocess.run(
        [sys.executable, str(GENERATE_SCRIPT), "--date", "1990-01-01", "--time", "12:00", "--timezone", "Asia/Taipei"],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    if result.returncode != 0:
        failures.append(f"命盤產生器契約測試失敗：{result.stderr.strip()}")
        return failures
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        failures.append(f"命盤產生器輸出不是 JSON：{error}")
        return failures
    if not payload.get("factsComplete") or not payload.get("seedsValidated"):
        failures.append("命盤產生器沒有完成 facts 或 seeds 驗證")
    if payload.get("expectedFactCount") != 58 or len(payload.get("facts", [])) != 58 or len(payload.get("seeds", [])) != 19:
        failures.append("命盤產生器的 facts 或 seeds 數量不符")
    fact_manifest = {
        "schemaVersion": payload.get("schemaVersion"),
        "ruleSet": payload.get("ruleSet"),
        "expectedFactIDs": payload.get("expectedFactIDs"),
    }
    if payload.get("factManifestSha256") != canonical_sha256(fact_manifest):
        failures.append("fact manifest hash 不符")
    if payload.get("seedContractSha256") != canonical_sha256(contract):
        failures.append("seed contract hash 不符")
    return failures


def check_relations(text: str) -> list[str]:
    failures: list[str] = []
    rows: dict[str, tuple[str, str, str]] = {}
    pattern = re.compile(r"^\| `structure\.relation\.([a-z]+)` \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|$", re.MULTILINE)
    name_to_id = {name: identifier for identifier, name in PALACE_NAMES.items()}
    for match in pattern.finditer(text):
        identifier = match.group(1)
        values = tuple(name_to_id[value.strip()] for value in match.groups()[2:])
        rows[identifier] = values  # type: ignore[assignment]
    for index, palace in enumerate(PALACES):
        expected = (PALACES[(index + 4) % 12], PALACES[(index + 8) % 12], PALACES[(index + 6) % 12])
        if rows.get(palace) != expected:
            failures.append(f"{palace} 三方四正 stable IDs 不正確")
    return failures


def check_language(paths: list[Path]) -> list[str]:
    failures: list[str] = []
    for path in paths:
        text = read_text(path)
        if not is_traditional(text):
            failures.append(f"{path.relative_to(REPOSITORY_ROOT)} 含可辨識的簡體中文")
        for wrong, preferred in AUTHORED_SIMPLIFIED_OR_NON_TAIWAN.items():
            if wrong in text:
                failures.append(f"{path.relative_to(REPOSITORY_ROOT)} 含「{wrong}」，應使用「{preferred}」")
    return failures


def check_product_contract() -> list[str]:
    failures: list[str] = []
    expected = {
        "Star": MAIN_STARS + SUPPORTING_STARS,
        "PalaceKind": PALACES,
        "TransformationKind": TRANSFORMATIONS,
    }
    for enum_name, values in expected.items():
        actual = declared_swift_cases(DOMAIN_PATHS[enum_name], enum_name)
        if set(actual) != set(values):
            failures.append(f"{enum_name}.allCases 與知識清單不同步")
    ruleset = read_text(RULESET)
    if "natal.star.ziWei.palace" not in ruleset or "natal.star.ziwei.palace" in ruleset:
        failures.append("RULESET.md 的紫微 fact ID 與 Star.rawValue 不一致")
    boundaries = read_text(PRODUCT_BOUNDARIES)
    for marker in (
        "InterpretationSection",
        "`evidenceSeedIDs` 與 `evidenceFactIDs`",
        "產品 validator 通過",
        "不能宣稱",
        "後續產品工作",
    ):
        if marker not in boundaries:
            failures.append(f"產品整合邊界缺少：{marker}")
    return failures


def run_self_test(modern: str) -> list[str]:
    failures: list[str] = []
    harmful_sentences = (
        "此人鐵定犯罪、傾家蕩產而且壽元很短。",
        "用來判定此人一生窮困潦倒，而且陽壽短促。",
        "觀察可知此人婚緣破敗，終身難有善終。",
        "可以斷定此人子嗣無望，終身孤苦。",
        "可表示此人命中帶殘，難逃牢獄之災。",
    )
    for sentence in harmful_sentences:
        harmful = modern.replace("可能較重視掌握方向", sentence, 1)
        result = check_claim_sections(harmful, MAIN_STAR_NAMES, "modern.star.", ("功能核心", "可用資源", "可能張力", "可核對問題"), 3)
        if not any("宿命斷言" in failure for failure in result):
            failures.append(f"反例測試未攔截宿命斷言：{sentence}")
    duplicate = modern.replace("`modern.star.tianJi`", "`modern.star.ziWei`", 1)
    result = check_claim_sections(duplicate, MAIN_STAR_NAMES, "modern.star.", ("功能核心", "可用資源", "可能張力", "可核對問題"), 3)
    if not result:
        failures.append("反例測試未攔截錯誤或重複 claim ID")
    source_path = SOURCES / "quanshu-volume-1-foundations.md"
    source_text = read_text(source_path)
    empty_source = source_text.split("\n---\n", 1)[0] + "\n---\n\n本檔沒有任何古籍內容。\n"
    if body_sha256(empty_source) == body_sha256(source_text):
        failures.append("反例測試未攔截空白來源 hash")
    if valid_wikisource_url("https://example.invalid/7913704"):
        failures.append("反例測試未攔截錯誤來源 URL")
    if is_traditional("軟件数据"):
        failures.append("反例測試未攔截簡體中文")
    return failures


def main() -> int:
    arguments = parse_arguments()
    try:
        modern = read_text(MODERN_REFERENCE)
        evidence = read_text(SOURCE_EVIDENCE)
        skill = read_text(SKILL_FILE)
        matrix = read_text(SEED_MATRIX)
    except (FileNotFoundError, UnicodeDecodeError, json.JSONDecodeError) as error:
        print(f"錯誤：{error}")
        return 1

    main_claim_failures = check_claim_sections(modern, MAIN_STAR_NAMES, "modern.star.", ("功能核心", "可用資源", "可能張力", "可核對問題"), 3)
    supporting_claim_failures = check_claim_sections(modern, SUPPORTING_STAR_NAMES, "modern.star.", ("功能核心", "可用資源", "可能張力", "可核對問題", "不可推論"), 4)
    palace_claim_failures = check_claim_sections(modern, PALACE_NAMES, "modern.palace.", ("功能核心", "可核對問題", "不可推論"), 3)
    transformation_claim_failures = check_claim_sections(modern, TRANSFORMATION_NAMES, "modern.transformation.", ("功能核心", "固定句型"), 3)

    body_failures = [identifier for identifier in BODY_PALACES if f"`modern.body.{identifier}`" not in modern]
    for identifier in BODY_PALACES:
        match = re.search(rf"^- `modern\.body\.{identifier}`：(.*)$", modern, re.MULTILINE)
        if match and (unsafe_claim_value(match.group(1)) or not SAFE_FRAMING.search(match.group(1))):
            body_failures.append(f"{identifier} 身宮 claim 不符合非宿命語氣")
    scope_failures = check_authored_prose_safety(modern)
    for marker in ("不表示紫微斗數已獲科學驗證", "只有 fact 而沒有 approved seed", "一般知識回答", "editorial-pending-review"):
        if marker not in modern:
            scope_failures.append(f"缺少範圍標記：{marker}")

    source_failures = check_source_manifest(arguments.online) + check_evidence_ledger(evidence, arguments.online)
    seed_failures = check_seed_contract(skill, matrix, modern)
    relation_failures = check_relations(modern)
    integration_failures = []
    markdown_paths = [SKILL_FILE, *sorted(REFERENCES.glob("*.md"))]
    integration_failures.extend(check_local_links(markdown_paths))
    integration_failures.extend(check_product_contract())
    integration_failures.extend(check_language([SKILL_FILE, *sorted(REFERENCES.glob("*.md"))]))
    for path in SKILL_ROOT.rglob("*"):
        if path.is_file() and len(read_text(path).splitlines()) > 1000:
            integration_failures.append(f"超過 1,000 行：{path.relative_to(REPOSITORY_ROOT)}")
    self_test_failures = run_self_test(modern) if arguments.self_test else []

    items = (
        ScoreItem("範圍、權威狀態與安全", 10, tuple(scope_failures), "一般知識與個人解讀邊界"),
        ScoreItem("來源 provenance 與內容完整性", 15, tuple(source_failures), "revision 時間、hash、章節與逐項證據帳"),
        ScoreItem("十四主星 claim schema", 15, tuple(main_claim_failures), "14 顆主星的可解析欄位與安全語意"),
        ScoreItem("六吉六煞、祿存與天馬 claim schema", 15, tuple(supporting_claim_failures), "14 顆星的可解析欄位與安全語意"),
        ScoreItem("十二宮與身宮", 15, tuple(palace_claim_failures + body_failures), "12 宮與 6 種身宮落宮"),
        ScoreItem("生年四化與三方四正", 10, tuple(transformation_claim_failures + relation_failures), "四化句型與 stable ID 關係"),
        ScoreItem("approved seed 支援矩陣", 10, tuple(seed_failures), "seed 與 fact 的雙重證據及未支援停止條件"),
        ScoreItem("Skill 契約、產品邊界、語言與維護", 10, tuple(integration_failures + self_test_failures), "連結、enum、fact ID、產品限制、台灣正體中文與反例測試"),
    )

    total = sum(item.earned for item in items)
    print("紫微斗數本命盤 Skill 知識完整度")
    for item in items:
        detail = "；".join(item.failures) if item.failures else item.evidence
        print(f"- {item.name}: {item.earned}/{item.maximum}（{detail}）")
    print(f"- 外部 revision 狀態：{'已線上重查' if arguments.online else '使用本機已驗證 manifest；未要求即時網路'}")
    if arguments.self_test:
        print("- Checker 反例測試：通過" if not self_test_failures else "- Checker 反例測試：失敗")
    print(f"總分：{total}/100")
    return 0 if total == 100 else 1


if __name__ == "__main__":
    sys.exit(main())
