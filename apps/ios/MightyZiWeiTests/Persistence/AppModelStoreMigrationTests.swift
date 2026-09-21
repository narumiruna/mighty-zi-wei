import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
final class AppModelStoreMigrationTests: XCTestCase {
  func test共用路徑只列出主檔JournalSHM與WAL() {
    let base = URL(filePath: "/tmp/本機資料/default.store")
    XCTAssertEqual(
      AppModelStoreFiles.urls(for: base).map(\.lastPathComponent),
      ["default.store", "default.store-journal", "default.store-shm", "default.store-wal"])
  }

  func test複製失敗不發布主檔且清除暫存後可重試() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let source = root.appending(path: "來源/default.store")
    let destination = root.appending(path: "目的/default.store")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for file in AppModelStoreFiles.urls(for: source) {
      try Data(file.lastPathComponent.utf8).write(to: file)
    }
    XCTAssertThrowsError(
      try AppModelStoreMigrator(
        fileManager: FailingStoreCopyFileManager(), sourceURL: source, destinationURL: destination
      ).migrateIfNeeded())
    for file in AppModelStoreFiles.urls(for: destination) {
      XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
      XCTAssertFalse(FileManager.default.fileExists(atPath: file.path + ".migration"))
    }
    try AppModelStoreMigrator(sourceURL: source, destinationURL: destination).migrateIfNeeded()
    for (original, copied) in zip(
      AppModelStoreFiles.urls(for: source), AppModelStoreFiles.urls(for: destination))
    {
      XCTAssertEqual(try Data(contentsOf: copied), try Data(contentsOf: original))
    }
  }

  func test舊共享容器資料庫會在本機資料庫不存在時完整遷移() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "AppModelStoreMigratorTests.\(UUID().uuidString)")
    let sourceURL = root.appending(path: "group/default.store")
    let destinationURL = root.appending(path: "local/default.store")
    try FileManager.default.createDirectory(
      at: sourceURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: destinationURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let suffixes = ["", "-journal", "-shm", "-wal"]
    for suffix in suffixes {
      try Data("legacy\(suffix)".utf8).write(
        to: URL(filePath: sourceURL.path + suffix)
      )
    }
    try Data("incomplete".utf8).write(
      to: URL(filePath: destinationURL.path + "-wal")
    )

    try AppModelStoreMigrator(
      sourceURL: sourceURL,
      destinationURL: destinationURL
    ).migrateIfNeeded()

    for suffix in suffixes {
      let source = URL(filePath: sourceURL.path + suffix)
      let destination = URL(filePath: destinationURL.path + suffix)
      XCTAssertEqual(try Data(contentsOf: destination), try Data(contentsOf: source))
      XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
      XCTAssertFalse(
        FileManager.default.fileExists(atPath: destination.path + ".migration")
      )
    }
  }

  func test遷移後SwiftData可讀取舊共享容器資料() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "AppModelStoreMigratorIntegrationTests.\(UUID().uuidString)")
    let sourceURL = root.appending(path: "group/default.store")
    let destinationURL = root.appending(path: "local/default.store")
    let conversationID = UUID()
    let schema = Schema([SavedConversation.self])
    try FileManager.default.createDirectory(
      at: sourceURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    try autoreleasepool {
      let sourceContainer = try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(
          schema: schema, url: sourceURL, cloudKitDatabase: .none)
      )
      let context = ModelContext(sourceContainer)
      let turn = ChartConversationTurn(
        question: "舊問題", answer: "舊回答", evidenceFactIDs: ["natal.palace.life.branch"])
      context.insert(
        SavedConversation(
          id: conversationID,
          chartID: nil,
          chartName: "舊共享命盤",
          chartDetail: "1990/01/01　12:00",
          modelIdentifier: "legacy-model",
          title: "舊共享對話",
          turns: [turn]
        ))
      try context.save()
    }

    try AppModelStoreMigrator(
      sourceURL: sourceURL,
      destinationURL: destinationURL
    ).migrateIfNeeded()
    let destinationContainer = try ModelContainer(
      for: schema,
      configurations: ModelConfiguration(
        schema: schema, url: destinationURL, cloudKitDatabase: .none)
    )
    let migrated = try ModelContext(destinationContainer).fetch(
      FetchDescriptor<SavedConversation>(
        predicate: #Predicate { conversation in
          conversation.id == conversationID
        }
      )
    )

    XCTAssertEqual(migrated.count, 1)
    XCTAssertEqual(migrated.first?.title, "舊共享對話")
    XCTAssertEqual(migrated.first?.turns.first?.answer, "舊回答")
  }

  func test重建會清除舊共享與本機資料避免再次匯入() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "AppModelStoreResetTests.\(UUID().uuidString)")
    let sourceURL = root.appending(path: "group/default.store")
    let destinationURL = root.appending(path: "local/default.store")
    try FileManager.default.createDirectory(
      at: sourceURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: destinationURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let suffixes = ["", "-journal", "-shm", "-wal"]
    for suffix in suffixes {
      try Data("legacy\(suffix)".utf8).write(
        to: URL(filePath: sourceURL.path + suffix)
      )
      try Data("local\(suffix)".utf8).write(
        to: URL(filePath: destinationURL.path + suffix)
      )
    }

    try AppModelContainerLoader.resetPersistentStores(
      legacyStoreURL: sourceURL,
      destinationStoreURL: destinationURL
    )
    try AppModelStoreMigrator(
      sourceURL: sourceURL,
      destinationURL: destinationURL
    ).migrateIfNeeded()

    for suffix in suffixes {
      XCTAssertFalse(
        FileManager.default.fileExists(
          atPath: URL(filePath: sourceURL.path + suffix).path
        )
      )
      XCTAssertFalse(
        FileManager.default.fileExists(
          atPath: URL(filePath: destinationURL.path + suffix).path
        )
      )
    }
  }

  func test既有本機資料庫不會被舊共享容器資料覆寫() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "AppModelStoreMigratorTests.\(UUID().uuidString)")
    let sourceURL = root.appending(path: "group/default.store")
    let destinationURL = root.appending(path: "local/default.store")
    try FileManager.default.createDirectory(
      at: sourceURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: destinationURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("legacy".utf8).write(to: sourceURL)
    try Data("current".utf8).write(to: destinationURL)

    try AppModelStoreMigrator(
      sourceURL: sourceURL,
      destinationURL: destinationURL
    ).migrateIfNeeded()

    XCTAssertEqual(try Data(contentsOf: destinationURL), Data("current".utf8))
  }
}

private final class FailingStoreCopyFileManager: FileManager, @unchecked Sendable {
  override func copyItem(at source: URL, to destination: URL) throws {
    if source.path.hasSuffix("-wal") { throw CocoaError(.fileWriteOutOfSpace) }
    try super.copyItem(at: source, to: destination)
  }
}
