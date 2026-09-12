import CloudKit
import Foundation
import Observation
import SwiftData

struct ICloudSyncResult: Equatable, Sendable {
  let uploadedCount: Int
  let downloadedCount: Int
  let conflictCount: Int
}

@MainActor
protocol ICloudSynchronizing {
  func sync(
    charts: [SavedChart],
    insights: [SavedInsight],
    deletions: [CloudDeletion],
    modelContext: ModelContext
  ) async throws -> ICloudSyncResult
}

@MainActor
@Observable
final class ICloudSynchronizer {
  private let service: any ICloudSynchronizing

  init(service: any ICloudSynchronizing = ICloudSyncService()) {
    self.service = service
  }

  func sync(
    charts: [SavedChart],
    insights: [SavedInsight],
    deletions: [CloudDeletion],
    modelContext: ModelContext
  ) async throws -> ICloudSyncResult {
    _ = (charts, insights, deletions)
    let synchronizationContext = ModelContext(modelContext.container)
    synchronizationContext.autosaveEnabled = false
    let latestCharts = try synchronizationContext.fetch(FetchDescriptor<SavedChart>())
    let latestInsights = try synchronizationContext.fetch(FetchDescriptor<SavedInsight>())
    let latestDeletions = try synchronizationContext.fetch(FetchDescriptor<CloudDeletion>())
    return try await service.sync(
      charts: latestCharts,
      insights: latestInsights,
      deletions: latestDeletions,
      modelContext: synchronizationContext
    )
  }
}

enum ICloudSyncFailureState: Equatable, Sendable {
  case accountUnavailable
  case partialRemote

  var message: String {
    switch self {
    case .accountUnavailable:
      "同步未完成。請確認已登入 iCloud 並允許此 App 使用 iCloud，再重試。"
    case .partialRemote:
      "同步未完成，iCloud 可能已收到部分資料。本機資料仍保留，你可以安全地重試。"
    }
  }

  init(error: any Error) {
    if let syncError = error as? ICloudSyncService.SyncError,
      syncError == .iCloudUnavailable
    {
      self = .accountUnavailable
    } else if let cloudError = error as? CKError,
      cloudError.code == .notAuthenticated
        || cloudError.code == .permissionFailure
    {
      self = .accountUnavailable
    } else {
      self = .partialRemote
    }
  }
}

@MainActor
@Observable
final class ICloudSyncCoordinator {
  enum Status: Equatable {
    case idle
    case waiting
    case syncing
    case synced(ICloudSyncResult)
    case incomplete(ICloudSyncFailureState)
  }

  typealias Operation = @MainActor () async throws -> ICloudSyncResult

  private(set) var isSyncing = false
  private(set) var status: Status = .idle
  private var waiters: [UUID: CheckedContinuation<ICloudSyncResult, any Error>] = [:]
  private var pendingOperation: (id: UUID, operation: Operation)?
  var waitingCallerCount: Int { waiters.count }

  func markEnabledWaiting() {
    guard !isSyncing else { return }
    status = .waiting
  }

  func markDisabled() {
    guard !isSyncing else { return }
    status = .idle
  }

  func synchronize(
    operation: @escaping Operation
  ) async throws -> ICloudSyncResult {
    if isSyncing {
      let identifier = UUID()
      pendingOperation = (identifier, operation)
      return try await waitForCurrentSync(identifier: identifier)
    }

    isSyncing = true
    status = .syncing
    var currentOperation = operation
    var combinedResult = ICloudSyncResult(
      uploadedCount: 0,
      downloadedCount: 0,
      conflictCount: 0
    )
    do {
      while true {
        let result = try await currentOperation()
        combinedResult = ICloudSyncResult(
          uploadedCount: combinedResult.uploadedCount + result.uploadedCount,
          downloadedCount: combinedResult.downloadedCount + result.downloadedCount,
          conflictCount: combinedResult.conflictCount + result.conflictCount
        )
        guard let trailing = pendingOperation else { break }
        pendingOperation = nil
        currentOperation = trailing.operation
      }
      isSyncing = false
      status = .synced(combinedResult)
      resumeWaiters(with: .success(combinedResult))
      return combinedResult
    } catch {
      isSyncing = false
      pendingOperation = nil
      status = .incomplete(ICloudSyncFailureState(error: error))
      resumeWaiters(with: .failure(error))
      throw error
    }
  }

  private func waitForCurrentSync(identifier: UUID) async throws -> ICloudSyncResult {
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          waiters[identifier] = continuation
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.cancelWaiter(identifier)
      }
    }
  }

  private func cancelWaiter(_ identifier: UUID) {
    if pendingOperation?.id == identifier {
      pendingOperation = nil
    }
    waiters.removeValue(forKey: identifier)?.resume(
      throwing: CancellationError()
    )
  }

  private func resumeWaiters(
    with result: Result<ICloudSyncResult, any Error>
  ) {
    let currentWaiters = waiters.values
    waiters.removeAll()
    for waiter in currentWaiters {
      switch result {
      case .success(let value): waiter.resume(returning: value)
      case .failure(let error): waiter.resume(throwing: error)
      }
    }
  }
}

@MainActor
enum CloudSyncMutationTransaction {
  static func run<Result>(
    modelContext: ModelContext,
    onRollback: () -> Void = {},
    operation: () async throws -> Result
  ) async throws -> Result {
    do {
      return try await operation()
    } catch {
      modelContext.rollback()
      onRollback()
      throw error
    }
  }
}
