import Foundation
import SwiftData

/// 先檢查所有不可覆寫內容，再與既有還原共用同一次 save。
struct ObservationRestorePlan {
  let observationsToInsert: [SavedObservation]
  let reviewsToInsert: [SavedObservationReview]
  let existingObservations: [SavedObservation]
  let existingReviews: [SavedObservationReview]
  let incomingObservationRevisions: [UUID: Date]
  let incomingReviewRevisions: [UUID: Date]

  init(payload: ValidatedBackupPayload, modelContext: ModelContext) throws {
    let observations = try modelContext.fetch(FetchDescriptor<SavedObservation>())
    let reviews = try modelContext.fetch(FetchDescriptor<SavedObservationReview>())
    let observationsByID = Dictionary(uniqueKeysWithValues: observations.map { ($0.id, $0) })
    let reviewsByID = Dictionary(uniqueKeysWithValues: reviews.map { ($0.id, $0) })
    var newObservations: [SavedObservation] = []
    var newReviews: [SavedObservationReview] = []
    for incoming in payload.observations {
      if let existing = observationsByID[incoming.id] {
        guard try incoming.hasSameContent(as: ObservationPayload(existing)) else {
          throw ObservationError.immutableConflict
        }
      } else {
        newObservations.append(try incoming.makeModel())
      }
    }
    for incoming in payload.reviews {
      if let existing = reviewsByID[incoming.id] {
        guard try incoming.hasSameContent(as: ObservationReviewPayload(existing)) else {
          throw ObservationError.immutableConflict
        }
      } else {
        newReviews.append(try incoming.makeModel())
      }
    }
    observationsToInsert = newObservations
    reviewsToInsert = newReviews
    existingObservations = payload.observations.compactMap { observationsByID[$0.id] }
    existingReviews = payload.reviews.compactMap { reviewsByID[$0.id] }
    incomingObservationRevisions = Dictionary(
      uniqueKeysWithValues: payload.observations.map { ($0.id, $0.modifiedAt) }
    )
    incomingReviewRevisions = Dictionary(
      uniqueKeysWithValues: payload.reviews.map { ($0.id, $0.modifiedAt) }
    )
  }

  func apply(modelContext: ModelContext, revision: Date) {
    observationsToInsert.forEach(modelContext.insert)
    reviewsToInsert.forEach(modelContext.insert)
    for observation in existingObservations + observationsToInsert {
      observation.modifiedAt = max(
        max(
          observation.modifiedAt,
          incomingObservationRevisions[observation.id] ?? revision
        ),
        revision
      )
    }
    for review in existingReviews + reviewsToInsert {
      review.modifiedAt = max(
        max(
          review.modifiedAt,
          incomingReviewRevisions[review.id] ?? revision
        ),
        revision
      )
    }
  }
}
