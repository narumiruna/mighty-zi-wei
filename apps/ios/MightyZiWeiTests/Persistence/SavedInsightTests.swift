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

    func test刪除命盤前摘要明確列出筆記與收藏數量() {
        let chartID = UUID()
        let summary = SavedInsightDeletionSummary(insights: [
            SavedInsight(
                chartID: chartID,
                kind: .note,
                locationID: "chart.general",
                title: "私人筆記",
                content: "內容"
            ),
            SavedInsight.bookmark(
                chartID: chartID,
                locationID: "interpretation.overview",
                title: "收藏",
                content: "內容",
                evidenceFactIDs: []
            )
        ])

        XCTAssertEqual(summary.noteCount, 1)
        XCTAssertEqual(summary.bookmarkCount, 1)
        XCTAssertEqual(summary.message, "將一併永久刪除 1 則私人筆記與 1 則收藏。這個動作無法復原。")
    }

    func test重新產生內容後可辨識並更新同一收藏() {
        let bookmark = SavedInsight.bookmark(
            chartID: UUID(),
            locationID: "interpretation.ai.overview",
            title: "原始標題",
            content: "原始內容",
            evidenceFactIDs: ["fact.original"]
        )
        let originalID = bookmark.id

        XCTAssertTrue(bookmark.matchesBookmark(
            title: "原始標題",
            content: "原始內容",
            evidenceFactIDs: ["fact.original"]
        ))
        XCTAssertFalse(bookmark.matchesBookmark(
            title: "更新標題",
            content: "更新內容",
            evidenceFactIDs: ["fact.updated"]
        ))

        bookmark.updateBookmark(
            title: "更新標題",
            content: "更新內容",
            evidenceFactIDs: ["fact.updated"]
        )

        XCTAssertEqual(bookmark.id, originalID)
        XCTAssertEqual(bookmark.title, "更新標題")
        XCTAssertEqual(bookmark.content, "更新內容")
        XCTAssertEqual(bookmark.evidenceFactIDs, ["fact.updated"])
        XCTAssertTrue(bookmark.matchesBookmark(
            title: "更新標題",
            content: "更新內容",
            evidenceFactIDs: ["fact.updated"]
        ))
    }
}
