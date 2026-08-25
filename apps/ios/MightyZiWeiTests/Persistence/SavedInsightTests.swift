import SwiftData
import XCTest
@testable import MightyZiWei

@MainActor
final class SavedInsightTests: XCTestCase {
    func test筆記可保存自我觀察標記() throws {
        let chartID = UUID()
        let insight = SavedInsight(
            chartID: chartID,
            kind: .note,
            locationID: "palace.life",
            title: "命宮筆記",
            content: "先觀察自己做決定的方式。",
            marker: .observe
        )
        let container = try ModelContainer(
            for: SavedChart.self,
            SavedInsight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(insight)
        try context.save()

        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<SavedInsight>()).first)
        XCTAssertEqual(restored.chartID, chartID)
        XCTAssertEqual(restored.kind, .note)
        XCTAssertEqual(restored.marker, .observe)
        XCTAssertEqual(restored.locationID, "palace.life")
    }

    func test收藏保留EvidenceFactIDs() throws {
        let evidence = [
            "natal.palace.life.branch",
            "natal.star.ziWei.palace"
        ]
        let bookmark = SavedInsight.bookmark(
            chartID: UUID(),
            locationID: "interpretation.overview",
            title: "命盤總覽",
            content: "收藏內容",
            evidenceFactIDs: evidence
        )

        XCTAssertEqual(bookmark.kind, .bookmark)
        XCTAssertEqual(bookmark.evidenceFactIDs, evidence)
        XCTAssertEqual(bookmark.marker, .none)
    }
}
