import Foundation

struct CloudObservationMergePlan {
  let observations: [ObservationPayload]
  let reviews: [ObservationReviewPayload]
  let deletions: [CloudObservationDeletion]

  init(
    local: CloudObservationState,
    remote: CloudObservationState,
    chartRevisions: [UUID: Date],
    chartDeletions: [UUID: Date],
    parentCharts: [UUID: ObservationParentChartEvidence]
  ) throws {
    try Self.validateRecords(local)
    try Self.validateRecords(remote)
    var accumulator = ObservationMergeAccumulator(
      chartRevisions: chartRevisions, chartDeletions: chartDeletions)
    for deletion in local.deletions + remote.deletions {
      accumulator.recordDeletion(
        key: CloudEntityKey(type: deletion.entityType, id: deletion.entityID),
        date: deletion.deletedAt)
    }
    for observation in local.observations + remote.observations {
      try accumulator.include(observation)
    }
    accumulator.removeDeletedObservations()
    for review in local.reviews + remote.reviews { try accumulator.include(review) }
    accumulator.removeDeletedReviews()
    observations = accumulator.observations.values.sorted { $0.id.uuidString < $1.id.uuidString }
    reviews = accumulator.reviews.values.sorted { $0.id.uuidString < $1.id.uuidString }
    deletions = Array(accumulator.deletions.values)
    try ObservationGraphValidator().validate(
      observations: observations,
      reviews: reviews,
      parentCharts: parentCharts
    )
  }

  private static func validateRecords(_ state: CloudObservationState) throws {
    guard Set(state.observations.map(\.id)).count == state.observations.count,
      Set(state.reviews.map(\.id)).count == state.reviews.count,
      Set(state.deletions.map { CloudEntityKey(type: $0.entityType, id: $0.entityID) }).count
        == state.deletions.count
    else { throw ObservationError.duplicateID }
    for observation in state.observations { try observation.validate() }
    for review in state.reviews { try review.validate() }
    for deletion in state.deletions { try deletion.validate() }
  }
}

private struct ObservationMergeAccumulator {
  let chartRevisions: [UUID: Date]
  let chartDeletions: [UUID: Date]
  var observations: [UUID: ObservationPayload] = [:]
  var reviews: [UUID: ObservationReviewPayload] = [:]
  var deletions: [CloudEntityKey: CloudObservationDeletion] = [:]

  private func chartIsDeleted(_ chartID: UUID) -> Bool {
    guard let deletion = chartDeletions[chartID] else { return false }
    return deletion >= chartRevisions[chartID] ?? .distantPast
  }

  mutating func include(_ observation: ObservationPayload) throws {
    let key = CloudEntityKey(type: RecordType.observation, id: observation.id)
    if chartIsDeleted(observation.chartID) {
      recordDeletion(
        key: key,
        date: max(chartDeletions[observation.chartID] ?? .distantPast, observation.modifiedAt))
    }
    if let deletedAt = deletions[key]?.deletedAt, deletedAt >= observation.modifiedAt { return }
    guard chartRevisions[observation.chartID] != nil else { throw ObservationError.missingParent }
    if let previous = observations[observation.id] {
      guard previous.hasSameContent(as: observation) else {
        throw ObservationError.immutableConflict
      }
      if previous.modifiedAt >= observation.modifiedAt { return }
    }
    observations[observation.id] = observation
  }

  mutating func include(_ review: ObservationReviewPayload) throws {
    let key = CloudEntityKey(type: RecordType.review, id: review.id)
    let parentDeletion = deletions[
      CloudEntityKey(type: RecordType.observation, id: review.observationID)]
    if chartIsDeleted(review.chartID)
      || (parentDeletion != nil && observations[review.observationID] == nil)
    {
      recordDeletion(
        key: key,
        date: max(
          max(
            chartDeletions[review.chartID] ?? .distantPast,
            parentDeletion?.deletedAt ?? .distantPast), review.modifiedAt))
    }
    if let deletedAt = deletions[key]?.deletedAt, deletedAt >= review.modifiedAt { return }
    guard observations[review.observationID]?.chartID == review.chartID else {
      throw ObservationError.missingParent
    }
    if let previous = reviews[review.id] {
      guard previous.hasSameContent(as: review) else { throw ObservationError.immutableConflict }
      if previous.modifiedAt >= review.modifiedAt { return }
    }
    reviews[review.id] = review
  }

  mutating func removeDeletedObservations() {
    observations = observations.filter { _, value in
      deletions[CloudEntityKey(type: RecordType.observation, id: value.id)].map {
        $0.deletedAt < value.modifiedAt
      } ?? true
    }
  }

  mutating func removeDeletedReviews() {
    reviews = reviews.filter { _, value in
      deletions[CloudEntityKey(type: RecordType.review, id: value.id)].map {
        $0.deletedAt < value.modifiedAt
      } ?? true
    }
  }

  mutating func recordDeletion(key: CloudEntityKey, date: Date) {
    guard date > deletions[key]?.deletedAt ?? .distantPast else { return }
    deletions[key] = CloudObservationDeletion(
      entityID: key.id, entityType: key.type, deletedAt: date)
  }
}
