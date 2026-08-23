import SwiftData
import XCTest
@testable import MightyZiWei

@MainActor
final class SavedChartTests: XCTestCase {
    func test儲存資料以BirthProfile為SourceOfTruth() throws {
        let profile = BirthProfile(
            localDate: LocalDate(year: 1990, month: 6, day: 15),
            localTime: LocalTime(hour: 10, minute: 30),
            timeZoneIdentifier: "Asia/Taipei"
        )
        let chart = try ZiWeiCalculator().calculate(profile)
        let saved = try SavedChart.make(name: "測試命盤", profile: profile, chart: chart)

        XCTAssertEqual(try saved.birthProfile(), profile)
        XCTAssertEqual(try saved.resolvedChart().stars, chart.stars)
        XCTAssertEqual(saved.ruleSetID, RuleSetIdentity.taiwanTraditionalSanheV1.id)
        XCTAssertEqual(saved.appSchemaVersion, SavedChart.schemaVersion)
    }

    func test不相容Cache會重新計算() throws {
        let profile = BirthProfile(
            localDate: LocalDate(year: 2024, month: 2, day: 10),
            localTime: LocalTime(hour: 0, minute: 30),
            timeZoneIdentifier: "Asia/Taipei"
        )
        let chart = try ZiWeiCalculator().calculate(profile)
        let saved = try SavedChart.make(name: "", profile: profile, chart: chart)
        saved.ruleSetVersion = 0
        saved.chartCacheData = Data("無效快取".utf8)

        let regenerated = try saved.resolvedChart()

        XCTAssertEqual(regenerated.ruleSet, .taiwanTraditionalSanheV1)
        XCTAssertEqual(saved.ruleSetVersion, 1)
        XCTAssertNotNil(try JSONDecoder().decode(ZiWeiChart.self, from: XCTUnwrap(saved.chartCacheData)))
    }

    func testSwiftData可新增重新命名與刪除() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SavedChart.self, configurations: configuration)
        let context = ModelContext(container)
        let profile = BirthProfile(
            localDate: LocalDate(year: 2000, month: 1, day: 1),
            localTime: LocalTime(hour: 12, minute: 0)
        )
        let saved = try SavedChart.make(
            name: "原名稱",
            profile: profile,
            chart: ZiWeiCalculator().calculate(profile)
        )

        context.insert(saved)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedChart>()).count, 1)

        try saved.rename(to: "新名稱")
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedChart>()).first?.name, "新名稱")

        context.delete(saved)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<SavedChart>()).isEmpty)
    }
}
