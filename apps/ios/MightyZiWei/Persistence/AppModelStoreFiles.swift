import Foundation

/// 主檔最後發布，避免把尚未完成 sidecar 搬移的資料庫視為可用。
enum AppModelStoreFiles {
  static func urls(for storeURL: URL) -> [URL] {
    ["", "-journal", "-shm", "-wal"].map { URL(filePath: storeURL.path + $0) }
  }
}

struct AppModelStoreMigrator {
  var fileManager = FileManager.default
  var sourceURL: URL
  var destinationURL: URL

  func migrateIfNeeded() throws {
    let sourceURL = sourceURL.standardizedFileURL
    let destinationURL = destinationURL.standardizedFileURL
    guard sourceURL != destinationURL,
      !fileManager.fileExists(atPath: destinationURL.path),
      fileManager.fileExists(atPath: sourceURL.path)
    else { return }

    let destinations = AppModelStoreFiles.urls(for: destinationURL)
    try fileManager.createDirectory(
      at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try cleanupTemporaryFiles(destinations)
    for sidecar in destinations.dropFirst() where fileManager.fileExists(atPath: sidecar.path) {
      try fileManager.removeItem(at: sidecar)
    }
    do {
      for (source, destination) in zip(AppModelStoreFiles.urls(for: sourceURL), destinations) {
        guard fileManager.fileExists(atPath: source.path) else { continue }
        try fileManager.copyItem(at: source, to: temporaryFile(for: destination))
      }
      for destination in destinations.dropFirst() {
        let temporary = temporaryFile(for: destination)
        guard fileManager.fileExists(atPath: temporary.path) else { continue }
        if fileManager.fileExists(atPath: destination.path) {
          try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
      }
      try fileManager.moveItem(at: temporaryFile(for: destinationURL), to: destinationURL)
    } catch {
      try? cleanupTemporaryFiles(destinations)
      throw error
    }
  }

  private func cleanupTemporaryFiles(_ destinations: [URL]) throws {
    for destination in destinations {
      let temporary = temporaryFile(for: destination)
      if fileManager.fileExists(atPath: temporary.path) {
        try fileManager.removeItem(at: temporary)
      }
    }
  }

  private func temporaryFile(for destination: URL) -> URL {
    URL(filePath: destination.path + ".migration")
  }
}

struct AppModelStoreResetter {
  var fileManager = FileManager.default
  var storeURL: URL

  func resetStoreFiles() throws {
    for file in AppModelStoreFiles.urls(for: storeURL)
    where fileManager.fileExists(atPath: file.path) {
      try fileManager.removeItem(at: file)
    }
  }
}
