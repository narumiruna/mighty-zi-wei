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
    XCTAssertTrue(restored.evidenceSeedIDs.isEmpty)
  }

  func test收藏保留Seed與FactEvidenceIDs() throws {
    let seedEvidence = ["seed.overview.ziWei.life"]
    let factEvidence = [
      "natal.palace.life.branch",
      "natal.star.ziWei.palace",
    ]
    let bookmark = SavedInsight.bookmark(
      chartID: UUID(),
      locationID: "interpretation.overview",
      title: "命盤總覽",
      content: "收藏內容",
      evidenceSeedIDs: seedEvidence,
      evidenceFactIDs: factEvidence
    )

    XCTAssertEqual(bookmark.kind, .bookmark)
    XCTAssertEqual(bookmark.evidenceSeedIDs, seedEvidence)
    XCTAssertEqual(bookmark.evidenceFactIDs, factEvidence)
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
      ),
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
      evidenceSeedIDs: ["seed.original"],
      evidenceFactIDs: ["fact.original"]
    )
    let originalID = bookmark.id

    XCTAssertTrue(
      bookmark.matchesBookmark(
        title: "原始標題",
        content: "原始內容",
        evidenceSeedIDs: ["seed.original"],
        evidenceFactIDs: ["fact.original"]
      ))
    XCTAssertFalse(
      bookmark.matchesBookmark(
        title: "更新標題",
        content: "更新內容",
        evidenceSeedIDs: ["seed.updated"],
        evidenceFactIDs: ["fact.updated"]
      ))

    bookmark.updateBookmark(
      title: "更新標題",
      content: "更新內容",
      evidenceSeedIDs: ["seed.updated"],
      evidenceFactIDs: ["fact.updated"]
    )

    XCTAssertEqual(bookmark.id, originalID)
    XCTAssertEqual(bookmark.title, "更新標題")
    XCTAssertEqual(bookmark.content, "更新內容")
    XCTAssertEqual(bookmark.evidenceSeedIDs, ["seed.updated"])
    XCTAssertEqual(bookmark.evidenceFactIDs, ["fact.updated"])
    XCTAssertTrue(
      bookmark.matchesBookmark(
        title: "更新標題",
        content: "更新內容",
        evidenceSeedIDs: ["seed.updated"],
        evidenceFactIDs: ["fact.updated"]
      ))
  }
}
