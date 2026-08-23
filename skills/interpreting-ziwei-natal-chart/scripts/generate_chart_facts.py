# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""使用專案的 Swift canonical ruleset 產生 ChartFact 與 InterpretationSeed。"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from datetime import date, time
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SWIFT_SOURCE_PATHS = (
    "apps/ios/MightyZiWei/Domain/BirthProfile.swift",
    "apps/ios/MightyZiWei/Domain/Celestial.swift",
    "apps/ios/MightyZiWei/Domain/Palace.swift",
    "apps/ios/MightyZiWei/Domain/Star.swift",
    "apps/ios/MightyZiWei/Domain/Transformation.swift",
    "apps/ios/MightyZiWei/Domain/ZiWeiChart.swift",
    "apps/ios/MightyZiWei/ZiWeiCore/Calendar/CalendarNormalizer.swift",
    "apps/ios/MightyZiWei/ZiWeiCore/Rules/ZiWeiRules.swift",
    "apps/ios/MightyZiWei/ZiWeiCore/Calculator/ZiWeiCalculator.swift",
    "apps/ios/MightyZiWei/Interpretation/InterpretationModels.swift",
    "apps/ios/MightyZiWei/Interpretation/ChartFactBuilder.swift",
    "apps/ios/MightyZiWei/Interpretation/InterpretationSeedBuilder.swift",
)

SWIFT_RUNNER = r'''
import Foundation

struct ScriptOutput: Encodable {
    let ruleSet: RuleSetIdentity
    let birthDate: String
    let birthTime: String
    let timeZoneIdentifier: String
    let lunarDate: LunarDate
    let hourBranch: String
    let facts: [ChartFact]
    let seeds: [InterpretationSeed]
}

enum ScriptError: Error {
    case invalidArguments
    case unexpectedFactIDs
    case duplicateFactID
    case missingEvidence(String)
}

@main
struct Main {
    static func main() throws {
        guard CommandLine.arguments.count == 7,
              let year = Int(CommandLine.arguments[1]),
              let month = Int(CommandLine.arguments[2]),
              let day = Int(CommandLine.arguments[3]),
              let hour = Int(CommandLine.arguments[4]),
              let minute = Int(CommandLine.arguments[5]) else {
            throw ScriptError.invalidArguments
        }

        let timeZoneIdentifier = CommandLine.arguments[6]
        let profile = BirthProfile(
            localDate: LocalDate(year: year, month: month, day: day),
            localTime: LocalTime(hour: hour, minute: minute),
            timeZoneIdentifier: timeZoneIdentifier
        )
        let chart = try ZiWeiCalculator().calculate(profile)
        let facts = ChartFactBuilder().makeFacts(from: chart)
        let factIDs = Set(facts.map(\.id))
        let expectedFactIDs = Set(
            ["natal.bureau", "natal.palace.body.branch"]
            + PalaceKind.allCases.flatMap {
                [
                    "natal.palace.\($0.rawValue).branch",
                    "natal.palace.\($0.rawValue).sanFangSiZheng"
                ]
            }
            + Star.allCases.map { "natal.star.\($0.rawValue).palace" }
            + TransformationKind.allCases.map { "natal.transformation.\($0.rawValue).star" }
        )

        guard factIDs.count == facts.count else {
            throw ScriptError.duplicateFactID
        }
        guard factIDs == expectedFactIDs else {
            throw ScriptError.unexpectedFactIDs
        }

        let seeds = InterpretationSeedBuilder().makeSeeds(from: facts)
        for evidenceID in seeds.flatMap(\.evidenceFactIDs) where !factIDs.contains(evidenceID) {
            throw ScriptError.missingEvidence(evidenceID)
        }

        let output = ScriptOutput(
            ruleSet: chart.ruleSet,
            birthDate: String(format: "%04d-%02d-%02d", year, month, day),
            birthTime: String(format: "%02d:%02d", hour, minute),
            timeZoneIdentifier: timeZoneIdentifier,
            lunarDate: chart.lunarDate,
            hourBranch: chart.hourBranch.displayName,
            facts: facts,
            seeds: seeds
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(output))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
'''


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="使用 Mighty Zi Wei 的 canonical Swift 排盤器產生已驗證的命盤事實。"
    )
    parser.add_argument("--date", required=True, help="公曆當地日期，格式為 YYYY-MM-DD。")
    parser.add_argument("--time", required=True, help="出生地當地時間，格式為 HH:MM。")
    parser.add_argument(
        "--timezone",
        required=True,
        help="IANA 時區識別碼，例如 Asia/Taipei。",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="選填的 JSON 輸出路徑；未指定時寫至標準輸出。",
    )
    return parser.parse_args()


def validated_inputs(arguments: argparse.Namespace) -> tuple[date, time, str]:
    try:
        local_date = date.fromisoformat(arguments.date)
    except ValueError as error:
        raise ValueError("--date 必須是有效的公曆日期，格式為 YYYY-MM-DD。") from error

    try:
        local_time = time.fromisoformat(arguments.time)
    except ValueError as error:
        raise ValueError("--time 必須是有效時間，格式為 HH:MM。") from error

    if local_time.second or local_time.microsecond or local_time.tzinfo is not None:
        raise ValueError("--time 只接受精確至分鐘的當地時間，格式為 HH:MM。")

    try:
        ZoneInfo(arguments.timezone)
    except ZoneInfoNotFoundError as error:
        raise ValueError("--timezone 必須是有效的 IANA 時區識別碼。") from error

    return local_date, local_time, arguments.timezone


def generate_chart_json(local_date: date, local_time: time, timezone: str) -> str:
    source_files = [REPOSITORY_ROOT / path for path in SWIFT_SOURCE_PATHS]
    missing_files = [path for path in source_files if not path.is_file()]
    if missing_files:
        missing = "、".join(str(path) for path in missing_files)
        raise RuntimeError(f"找不到 Swift 排盤來源檔：{missing}")

    with tempfile.TemporaryDirectory(prefix="mighty-ziwei-") as temporary_directory:
        temporary_path = Path(temporary_directory)
        runner_path = temporary_path / "ChartFactsRunner.swift"
        executable_path = temporary_path / "generate-chart-facts"
        runner_path.write_text(SWIFT_RUNNER, encoding="utf-8")

        compile_result = subprocess.run(
            ["swiftc", "-o", str(executable_path), *map(str, source_files), str(runner_path)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if compile_result.returncode != 0:
            raise RuntimeError(f"Swift 排盤器編譯失敗：\n{compile_result.stderr.strip()}")

        result = subprocess.run(
            [
                str(executable_path),
                str(local_date.year),
                str(local_date.month),
                str(local_date.day),
                str(local_time.hour),
                str(local_time.minute),
                timezone,
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(f"Swift 排盤器執行失敗：\n{result.stderr.strip()}")

    json.loads(result.stdout)
    return result.stdout


def main() -> int:
    arguments = parse_arguments()
    try:
        local_date, local_time, timezone = validated_inputs(arguments)
        output = generate_chart_json(local_date, local_time, timezone)
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"錯誤：{error}", file=sys.stderr)
        return 1

    if arguments.output:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
