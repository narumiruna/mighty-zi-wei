"""驗證格式變更相容性，以及 seed 契約對竄改資料的拒絕行為。"""

from __future__ import annotations

import copy
from datetime import date, time
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import check_knowledge_coverage as checker
import generate_chart_facts as generator


class EnumParsingTests(unittest.TestCase):
    def test接受兩格四格與Tab縮排而不讀取Switch或其他Enum(self) -> None:
        for indent in ("  ", "    ", "\t"):
            with self.subTest(indent=repr(indent)):
                source = (
                    "public enum Example: String {\n"
                    f"{indent}case first, second\n"
                    f"{indent}case third\n"
                    "  var text: String {\n"
                    "    switch self {\n"
                    "    case .first: return \"測試\"\n"
                    "    default: return \"其他\"\n"
                    "    }\n"
                    "  }\n"
                    "}\n"
                    "public enum Another {\n"
                    "  case unrelated\n"
                    "}\n"
                )
                self.assertEqual(checker.swift_cases(source, "Example"), ("first", "second", "third"))

    def test產品Enum集合通過且缺項或新增未知項仍然失敗(self) -> None:
        self.assertEqual(checker.check_product_contract(), [])
        original_path = checker.DOMAIN_PATHS["Star"]
        source = original_path.read_text(encoding="utf-8")
        for replacement in ("", "unreviewed, "):
            with self.subTest(replacement=replacement), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "Star.swift"
                path.write_text(source.replace("case ziWei, ", f"case {replacement}", 1), encoding="utf-8")
                with patch.dict(checker.DOMAIN_PATHS, {"Star": path}):
                    self.assertIn("Star.allCases 與知識清單不同步", checker.check_product_contract())


class SeedContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.payload = json.loads(generator.generate_chart_json(date(1990, 1, 1), time(12, 0), "Asia/Taipei"))

    def test既有五個Baseline與十四主星精確契約仍然通過(self) -> None:
        validated = json.loads(generator.validated_payload(json.dumps(self.payload)))
        self.assertTrue(validated["factsComplete"])
        self.assertTrue(validated["seedsValidated"])
        self.assertEqual(len(validated["seeds"]), 19)
        self.assertEqual(len(validated["facts"]), 58)

    def testMeaning與Evidence或落宮被改寫時拒絕(self) -> None:
        for mutation in ("meaning", "evidence", "palace", "duplicate", "invented"):
            with self.subTest(mutation=mutation):
                payload = copy.deepcopy(self.payload)
                seed = next(item for item in payload["seeds"] if item["id"].count(".") == 3)
                if mutation == "meaning":
                    seed["meaning"] = "這是未經核准的新含義。"
                elif mutation == "evidence":
                    seed["evidenceFactIDs"] = ["natal.bureau"]
                elif mutation == "palace":
                    fact = next(item for item in payload["facts"] if item["id"] == seed["evidenceFactIDs"][0])
                    fact["value"]["identifier"] = "unknown"
                elif mutation == "duplicate":
                    payload["seeds"][0] = copy.deepcopy(payload["seeds"][1])
                else:
                    payload["seeds"].append({"id": "seed.unreviewed.combination"})
                with self.assertRaises(RuntimeError):
                    generator.validated_payload(json.dumps(payload))

    def test來源Hash竄改仍然拒絕而不略過驗證(self) -> None:
        contract = json.loads(generator.SEED_CONTRACT_PATH.read_text(encoding="utf-8"))
        contract["builderSourceSha256"] = "0" * 64
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "seed-contract.json"
            path.write_text(json.dumps(contract), encoding="utf-8")
            with patch.object(generator, "SEED_CONTRACT_PATH", path):
                with self.assertRaisesRegex(RuntimeError, "必須先更新並審核"):
                    generator.validated_payload(json.dumps(self.payload))


if __name__ == "__main__":
    unittest.main()
